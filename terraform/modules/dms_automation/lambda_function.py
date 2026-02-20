import boto3
import os
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)
dms = boto3.client('dms')

def lambda_handler(event, context):
    forward_arn = os.environ['FORWARD_TASK_ARN']
    reverse_arn = os.environ['REVERSE_TASK_ARN']

    # ARN에서 식별자 ID만 추출 (예: arn...:task:MY-TASK -> MY-TASK)
    def get_task_id(string):
        return string.split(':')[-1]

    logger.info(f"Full Event Received: {event}")

    if 'detail-type' in event and event['detail-type'] == "DMS Replication Task State Change":
        detail = event.get('detail', {})
        status = detail.get('status')
        # 이벤트에서 온 값 (보통 Task ID만 옴)
        event_resource = detail.get('resourceIdentifier', '')
        
        target_id = get_task_id(forward_arn)
        event_id = get_task_id(event_resource)

        logger.info(f"Comparing Event ID: {event_id} with Target ID: {target_id}")

        if event_id == target_id and status in ['failed', 'stopped']:
            logger.info(f"Forward Task ({event_id}) issue confirmed. Starting Reverse...")
            try:
                # 'resume-processing' 시도 후 실패하면 'start-replication' 고려
                dms.start_replication_task(
                    ReplicationTaskArn=reverse_arn, 
                    StartReplicationTaskType='resume-processing' 
                )
                logger.info("Successfully sent resume command to Reverse Task.")
            except Exception as e:
                logger.warning(f"Resume failed, trying full start: {str(e)}")
                dms.start_replication_task(
                    ReplicationTaskArn=reverse_arn, 
                    StartReplicationTaskType='start-replication'
                )
    
    return {"message": "Process completed"}
