"""
Lambda function — TP1 HA Pritunl
Déclenchée à chaque upload sur le bucket S3.
Logge les événements et peut être étendue pour traitement custom.
"""

import json
import logging
import os
from urllib.parse import unquote_plus

import boto3

# Configuration du logger
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Variables d'environnement
S3_BUCKET = os.environ.get("S3_BUCKET", "")
DB_HOST = os.environ.get("DB_HOST", "")
DB_NAME = os.environ.get("DB_NAME", "")
DB_USER = os.environ.get("DB_USER", "")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

s3_client = boto3.client("s3")


def lambda_handler(event, context):
    """
    Handler principal — traite les événements S3.
    Pour chaque objet uploadé, on log les métadonnées et la taille.
    """
    logger.info(f"Événement reçu: {json.dumps(event)}")

    processed = []

    for record in event.get("Records", []):
        try:
            bucket = record["s3"]["bucket"]["name"]
            key = unquote_plus(record["s3"]["object"]["key"])
            event_name = record["eventName"]
            size = record["s3"]["object"].get("size", 0)

            logger.info(
                f"Traitement: bucket={bucket}, key={key}, "
                f"event={event_name}, size={size} bytes"
            )

            # Récupération des métadonnées de l'objet
            response = s3_client.head_object(Bucket=bucket, Key=key)
            content_type = response.get("ContentType", "unknown")
            last_modified = response.get("LastModified", "")

            result = {
                "bucket": bucket,
                "key": key,
                "size_bytes": size,
                "content_type": content_type,
                "last_modified": str(last_modified),
                "event": event_name,
                "environment": ENVIRONMENT,
            }

            logger.info(f"Métadonnées: {json.dumps(result)}")
            processed.append(result)

            # Ici on pourrait écrire dans le RDS via pymysql par exemple
            # save_to_rds(result)

        except Exception as e:
            logger.error(f"Erreur lors du traitement: {str(e)}", exc_info=True)
            raise

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Traitement terminé",
            "processed_count": len(processed),
            "items": processed,
        }),
    }
