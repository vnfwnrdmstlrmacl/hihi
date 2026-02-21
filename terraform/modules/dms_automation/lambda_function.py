import boto3
import os
import logging
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)
dms = boto3.client('dms')

def lambda_handler(event, context):
    forward_arn = os.environ.get('FORWARD_TASK_ARN', '').strip()
    reverse_arn = os.environ.get('REVERSE_TASK_ARN', '').strip()
    
    if not forward_arn or not reverse_arn:
        logger.error("Environment variables for ARNs are missing.")
        return {"status": "error", "message": "Missing ARNs"}

    logger.info("========== DMS AUTOMATION PROCESS START ==========")
    
    # 1. 태스크 상태 실시간 조회 (상세 정보 포함)
    try:
        tasks = dms.describe_replication_tasks(
            Filters=[{'Name': 'replication-task-arn', 'Values': [forward_arn, reverse_arn]}]
        )['ReplicationTasks']
        
        f_task = next(t for t in tasks if t['ReplicationTaskArn'] == forward_arn)
        r_task = next(t for t in tasks if t['ReplicationTaskArn'] == reverse_arn)
    except Exception as e:
        logger.error(f"Failed to fetch DMS tasks: {str(e)}")
        return {"status": "api_error"}

    f_status = f_task['Status']
    r_status = r_task['Status']
    source = event.get("source", "")

    # [보호 로직] 상태 변경 중(과도기)일 때는 중복 명령 방지를 위해 종료
    TRANSITION_STATES = ['starting', 'stopping', 'deleting', 'creating', 'modifying']
    if f_status in TRANSITION_STATES or r_status in TRANSITION_STATES:
        logger.info(f"Tasks in transition (F:{f_status}, R:{r_status}). Skipping this run.")
        return {"status": "transition_skip"}

    # --- 1단계: 장애 발생 시 역방향 가동 (EventBridge - DMS Event Trigger) ---
    if source == "aws.dms":
        resources = event.get('resources', [])
        if any(forward_arn.lower() in res.lower() for res in resources):
            if f_status in ['stopped', 'failed'] and r_status in ['ready', 'stopped']:
                logger.info(f"!!! DISRUPTION DETECTED: Starting Reverse Task (Forward: {f_status})")
                try:
                    # 가급적 CDC 지점부터 이어서 시작(resume), 실패 시 처음부터(start)
                    dms.start_replication_task(ReplicationTaskArn=reverse_arn, StartReplicationTaskType='resume-processing')
                except Exception:
                    dms.start_replication_task(ReplicationTaskArn=reverse_arn, StartReplicationTaskType='start-replication')
        return {"status": "failover_initiated"}

    # --- 2단계: 동기화 완료 시 정방향 복구 (EventBridge - Schedule Trigger) ---
    elif source == "aws.events":
        stats = r_task.get('ReplicationTaskStats', {})
        latency = stats.get('CDCLatencySource')
        start_time = r_task.get('ReplicationTaskStartDate')
        uptime = (datetime.now(timezone.utc) - start_time).total_seconds() if start_time else 0
        
        logger.info(f"Monitor - Reverse: {r_status}, Uptime: {uptime:.1f}s, Latency: {latency}")

        # 로직 A: 역방향 동기화가 완료되었을 때 -> 역방향 중지 명령
        if r_status == 'running' and uptime > 60: # 최소 1분 가동 후 판단
            # Latency가 안정적(10초 미만)일 때 스위칭 준비
            if latency is not None and latency < 10:
                if f_status in ['stopped', 'failed', 'ready']:
                    logger.info("!!! SYNC STABLE: Stopping Reverse Task for Failback...")
                    dms.stop_replication_task(ReplicationTaskArn=reverse_arn)
                    return {"status": "stopping_reverse"}

        # 로직 B: 역방향이 안전하게 멈췄을 때 -> 정방향 재가동 (매우 중요)
        if r_status == 'stopped' and f_status in ['stopped', 'failed', 'ready']:
            logger.info("!!! REVERSE STOPPED: Safely restarting Forward Task...")
            dms.start_replication_task(ReplicationTaskArn=forward_arn, StartReplicationTaskType='resume-processing')
            return {"status": "failback_complete"}

    return {"status": "no_action_needed"}
