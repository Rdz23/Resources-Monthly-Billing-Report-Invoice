# Resources-Monthly-Billing-Report-Invoice

## 1. Description
This automation generates a monthly AWS billing summary by resource (EC2, RDS, FSx), merged with a tag audit file to include meaningful ResourceName values.

It is powered by AWS Cost and Usage Reports (CUR) and outputs both TXT and CSV files to S3.
An SNS notification is then sent with a pre-signed CSV download link for quick access.

Features:
* Filters billing data for the previous month
* Falls back to defaults for untagged resources
* Uploads TXT/CSV outputs to S3
* Sends SNS notification with a pre-signed CSV link

## 2. Current Problem
When managing multiple EC2, RDS, FSx (e.g., each owned by different departments or clients), it’s often challenging to split billing per resources.
AWS’s default Billing dashboard lacks the granularity needed for detailed cost breakdowns.

This automation solves the problem by:
Identifying each EC2, RDS and FSx resources costing every month for tracking purposes or for billing on each resources used.
Mapping costs to Invoice IDs
Enabling chargeback/cross-charge per EC2, RDS and FSx
Providing a monthly summary of all active resources transactions

## 3. Diagram
<img width="667" height="118" alt="image" src="https://github.com/user-attachments/assets/2100825f-1f88-4c60-9231-0ec6cd3d1633" />

## 4. Schedule of Report
   Frequency: Monthly \
   Day: 5th of the month \ 
   Time: 07:00 UTC (15:00 PHT) \
 Trigger: AWS EventBridge rule → Lambda execution → S3 upload & SNS notification

## 5. Repository Structure
<img width="742" height="230" alt="image" src="https://github.com/user-attachments/assets/d82321f0-6e06-45cf-87a3-ce1348e8ed72" />


## 6. Deployment Steps

Step 1 – Upload Lambda.zip to AWS and named as resources-invoice-summary \
aws lambda create-function \
  --function-name resources-invoice-summary  \
  --runtime python3.12 \
  --role arn:aws:iam::<ACCOUNT_ID>:role/<LAMBDA_ROLE> \
  --handler resources-invoice-summary.lambda_handler \
  --zip-file fileb://lambda.zip

Step 2 – Create EventBridge Schedule \
aws events put-rule \
  --name "resources-monthly-summary-schedule" \
  --schedule-expression "cron(0 7 5 * ? *)"

Step 3 – Add EventBridge Permission to Lambda \
aws lambda add-permission \
  --function-name resources-invoice-summary  \
  --statement-id eventbridge-monthly-trigger \
  --action 'lambda:InvokeFunction' \
  --principal events.amazonaws.com \
  --source-arn arn:aws:events:<REGION>:<ACCOUNT_ID>:rule/resources-monthly-summary-schedule

Step 4 – Set Up SNS Topic & Subscription \
aws sns create-topic --name resources-billing-report
aws sns subscribe \
  --topic-arn arn:aws:sns:<REGION>:<ACCOUNT_ID>:resources-billing-report \
  --protocol email \
  --notification-endpoint your_email@example.com

## 7. Example Output
AWS Resource Invoice Summary (July-2025)

Invoice ID: 1234567890

CSV Report: aws-resources-billing-report-July-2025.csv

Download Pre-Signed URL: https://s3.ap-southeast-1.amazonaws.com/my-route53-billing-main/...
(Link expires in 3 days)



