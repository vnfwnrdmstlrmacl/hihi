import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
dms = boto3.client('dms')

def lambda_handler(event, context):
    forward_arn = os.environ['FORWARD_TASK_ARN']
    reverse_arn = os.environ['REVERSE_TASK_ARN']

    logger.info(f"Received Event: {event}")

    # EventBridge에서 전달된 상세 정보 추출
    detail = event.get('detail', {})
    status = detail.get('status')
    # resourceIdentifier는 보통 'arn:aws:dms:region:account:task:ID' 형태임
    resource_id = detail.get('resourceIdentifier', '')

    logger.info(f"Task Status: {status}, Resource: {resource_id}")

    # ID 비교 로직 개선: ARN에 forward_arn의 식별자가 포함되어 있는지 확인
    # 예: "test-migration-task"가 forward_arn(전체 ARN)의 끝부분인지 확인
    forward_task_name = forward_arn.split(':')[-1]
    
    if forward_task_name in resource_id and status in ['failed', 'stopped']:
        logger.info(f"Target Task ({forward_task_name}) issue detected. Action: Starting Reverse Task.")
        
        try:
            # CDC 모드이므로 resume-processing 시도
            dms.start_replication_task(
                ReplicationTaskArn=reverse_arn,
                StartReplicationTaskType='resume-processing'
            )
            logger.info("Successfully sent command: resume-processing")
        except Exception as e:
            logger.warning(f"Resume failed, trying start-replication: {str(e)}")
            dms.start_replication_task(
                ReplicationTaskArn=reverse_arn,
                StartReplicationTaskType='start-replication'
            )
    else:
        logger.info("Event does not match target task or status. No action taken.")
    
    return {"message": "Process completed"}
