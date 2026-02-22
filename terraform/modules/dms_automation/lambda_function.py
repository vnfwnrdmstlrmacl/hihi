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
    
    logger.info(f"Current Status - Forward: {f_status}, Reverse: {r_status}, Source: {source}")

    # --- 1단계: 장애 발생 시 역방향 가동 (Failover) ---
    if source == "aws.dms":
        resources = event.get('resources', [])
        if any(forward_arn.lower() in res.lower() for res in resources):
            if f_status in ['stopped', 'stopping', 'failed'] and r_status in ['ready', 'stopped']:
                logger.info(f"!!! DISRUPTION DETECTED: Starting Reverse Task")
                try:
                    # 우선 resume 시도
                    dms.start_replication_task(ReplicationTaskArn=reverse_arn, StartReplicationTaskType='resume-processing')
                except Exception as e:
                    logger.warning(f"Resume failed, trying start-replication: {str(e)}")
                    dms.start_replication_task(ReplicationTaskArn=reverse_arn, StartReplicationTaskType='start-replication')
                return {"status": "failover_initiated"}
        return {"status": "dms_event_no_action"}

    # --- 2단계: 모니터링 및 복구 (Failback & Stuck Recovery) ---
    elif source == "aws.events":
        stats = r_task.get('ReplicationTaskStats', {})
        latency = stats.get('CDCLatencySource')
        start_time = r_task.get('ReplicationTaskStartDate')
        uptime = (datetime.now(timezone.utc) - start_time).total_seconds() if start_time else 0
        
        logger.info(f"Monitor - Uptime: {uptime:.1f}s, Latency: {latency}")

        # [로직 A] 역방향 태스크 상태 점검
        if r_status == 'running' and uptime > 60:
            # 1. 1분이 지났는데 Latency가 None이면 태스크가 멍 때리는 상태임
            if latency is None:
                logger.warning("!!! LATENCY IS NONE: Task is stuck. Force restarting with 'start-replication'...")
                # 기존 태스크 중지 후 새로 시작 (reload-target)
                try:
                    dms.stop_replication_task(ReplicationTaskArn=reverse_arn)
                except: pass
                
                dms.start_replication_task(
                    ReplicationTaskArn=reverse_arn, 
                    StartReplicationTaskType='start-replication' # 처음부터 다시 로드
                )
                return {"status": "force_restarting_reverse"}

            # 2. Latency가 안정권(10초 미만)이면 동기화 완료로 판단
            if latency is None or latency == 999999:
                if f_status in ['stopped', 'failed', 'ready']:
                    logger.info("!!! SYNC STABLE: Stopping Reverse Task for Failback...")
                    dms.stop_replication_task(ReplicationTaskArn=reverse_arn)
                    return {"status": "stopping_reverse"}

        # [로직 B] 역방향 정지 완료 -> 정방향 재가동
        if r_status in ['stopped', 'ready'] and f_status in ['stopped', 'failed', 'ready']:
            if f_status != 'starting':
                logger.info("!!! REVERSE SAFE: Restarting Forward Task...")
                dms.start_replication_task(ReplicationTaskArn=forward_arn, StartReplicationTaskType='resume-processing')
                return {"status": "failback_complete"}

    return {"status": "no_action_needed"}
