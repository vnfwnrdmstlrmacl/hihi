import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
dms = boto3.client('dms')

def lambda_handler(event, context):
    # 환경 변수에서 정방향/역방향 ARN을 가져옴
    forward_arn = os.environ.get('FORWARD_TASK_ARN', '')
    reverse_arn = os.environ.get('REVERSE_TASK_ARN', '')

    logger.info("========== DMS AUTOMATION PROCESS START ==========")
    
    # 공통 데이터 추출
    source = event.get("source", "")
    resources = event.get('resources', [])
    event_task_arn = resources[0] if resources else ""
    detail = event.get('detail', {})
    detail_str = str(detail).lower()

    # [Case A] EventBridge Schedule 이벤트 (5분 주기) -> Failback 체크 로직
    if source == "aws.events":
        logger.info(">>> Schedule Event: Checking if Failback is needed...")
        try:
            # 역방향 태스크 상태 및 지연 시간 조회
            response = dms.describe_replication_tasks(
                Filters=[{'Name': 'replication-task-arn', 'Values': [reverse_arn]}]
            )
            
            if not response['ReplicationTasks']:
                logger.error("Reverse Task not found. Check REVERSE_TASK_ARN.")
                return {"status": "reverse_task_not_found"}

            task = response['ReplicationTasks'][0]
            status = task['Status']
            stats = task.get('ReplicationTaskStats', {})
            # Latency 값이 없을 경우를 대비해 기본값 설정
            latency = stats.get('CDCLatencySource', 999999)

            logger.info(f"Reverse Task Status: {status}, Latency: {latency}s")

            # 조건: 역방향이 실행 중이고, 데이터 동기화가 거의 완료(지연 10초 이내)되었을 때
            if status == 'running' and latency <= 10:
                logger.info("!!! SYNC COMPLETE: Starting Failback to Forward Task...")
                
                # 1. 역방향 중지
                dms.stop_replication_task(ReplicationTaskArn=reverse_arn)
                logger.info("Reverse Task Stop command sent.")
                
                # 2. 정방향 재시작
                dms.start_replication_task(
                    ReplicationTaskArn=forward_arn,
                    StartReplicationTaskType='resume-processing'
                )
                logger.info("SUCCESS: Failback to Forward Task initiated.")
            else:
                logger.info("Failback condition not met (Sync in progress or task not running).")
                
        except Exception as e:
            logger.error(f"Failback check failed: {e}")
        return {"status": "failback_check_done"}

    # [Case B] DMS State Change 이벤트 -> Failover 로직
    if source == "aws.dms":
        logger.info(f">>> DMS Event Detected: Task ARN = {event_task_arn}")
        
        # [수정 포인트] == 대신 'in'을 사용하여 ARN 매칭 신뢰도 상승
        if forward_arn in event_task_arn or event_task_arn in forward_arn:
            # 중지/실패 관련 키워드가 있는지 확인
            if any(kw in detail_str for kw in ['stop', 'fail', 'terminate', 'error']):
                logger.info("!!! MATCH FOUND: Forward Task is DOWN. Starting Reverse Task...")
                try:
                    dms.start_replication_task(
                        ReplicationTaskArn=reverse_arn,
                        StartReplicationTaskType='resume-processing'
                    )
                    logger.info("SUCCESS: Reverse Task Start Command Sent (Resume).")
                except Exception as e:
                    logger.warning(f"Resume failed, trying full start: {e}")
                    dms.start_replication_task(
                        ReplicationTaskArn=reverse_arn,
                        StartReplicationTaskType='start-replication'
                    )
                    logger.info("SUCCESS: Reverse Task Start Command Sent (Full Start).")
            else:
                logger.info(f"Forward task status change ignored (Detail: {detail_str[:100]}...).")
        else:
            # 이 로그가 찍힌다면 환경 변수의 ARN과 실제 발생 ARN이 다른 것입니다.
            logger.info(f"Mismatch! Expected: {forward_arn}, Got: {event_task_arn}")

    return {"status": "process_completed"}
