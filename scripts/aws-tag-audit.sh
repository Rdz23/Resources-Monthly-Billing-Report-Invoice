#!/bin/bash   

echo -n "Enter AWS region (e.g., ap-southeast-1): "
read REGION

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_FILE="tag-audit-${TIMESTAMP}.txt"
S3_BUCKET="rcn-tag-audit"
SNS_TOPIC_ARN="arn:aws:sns:ap-southeast-1:665634427675:TagAuditAlerts"

echo "Starting tag audit in region: $REGION"
echo

# Table header with updated column names and corrected spacing
echo "Rsource-Type   | Resource-Name    | Resource-ID           | Company      | Business-Unit   | Department  | CostCenter   | Tagged"
echo "──────────────+────────────────+─────────────────────+─────────────+────────────+──────────+──────────────+────────────+──────"
RESULTS=()
UNTAGGED=()

# Adjust column widths based on your example
print_line() {
    printf "%-15s | %-16s | %-20s | %-12s | %-15s | %-12s | %-12s | %-6s\n" "$1" "$2" "$3" "$4" "$5" "$6" "$7"
}

collect_tags() {
    local id=$1
    local type=$2
    local tag_cmd=$3

    # Fetch MetadataName for EC2 instances using the "Name" tag as metadata name
    if [[ "$type" == "ec2:instance" ]]; then
        # Use "Name" tag as the MetadataName for EC2 instances
        resource_name=$(aws ec2 describe-instances --instance-ids "$id" --region "$REGION" --query "Reservations[].Instances[].Tags[?Key=='Name'].Value" --output text)
    else
        resource_name=""
    fi

    # Fetch other tags as string values
    company=$($tag_cmd --filters "Name=resource-id,Values=$id" "Name=key,Values=Company" --region "$REGION" --output text 2>/dev/null | awk '{print $5}')
    business_unit=$($tag_cmd --filters "Name=resource-id,Values=$id" "Name=key,Values=Business Unit" --region "$REGION" --output text 2>/dev/null | awk '{print $5}')
    department=$($tag_cmd --filters "Name=resource-id,Values=$id" "Name=key,Values=Department" --region "$REGION" --output text 2>/dev/null | awk '{print $5}')
    cost_center=$($tag_cmd --filters "Name=resource-id,Values=$id" "Name=key,Values=CostCenter" --region "$REGION" --output text 2>/dev/null | awk '{print $5}')

    # Set empty values to blank
    if [[ -z "$company" ]]; then
        company=""
    fi
    if [[ -z "$business_unit" ]]; then
        business_unit=""
    fi
    if [[ -z "$department" ]]; then
        department=""
    fi
    if [[ -z "$cost_center" ]]; then
        cost_center=""
    fi

    # Determine if the resource is tagged based on Company, Department, and CostCenter
    if [[ -n "$company" && -n "$department" && -n "$cost_center" ]]; then
        is_tagged="Yes"
    else
        is_tagged="No"
    fi

    # Format the output line
    line=$(print_line "$type" "$resource_name" "$id" "$company" "$business_unit" "$department" "$cost_center" "$is_tagged")
    echo "$line"
    RESULTS+=("$line")

    if [[ "$is_tagged" == "No" ]]; then
        UNTAGGED+=("$line")
    fi
}

# Audit EC2 Instances
echo "Checking: ec2:instance..."
instance_ids=$(aws ec2 describe-instances --region "$REGION" --query 'Reservations[].Instances[].InstanceId' --output text)
for id in $instance_ids; do
    collect_tags "$id" "ec2:instance" "aws ec2 describe-tags"
done

# Audit RDS Instances
echo "Checking: rds:db-instance..."
rds_instances=$(aws rds describe-db-instances --region "$REGION" --query 'DBInstances[].DBInstanceIdentifier' --output text)
for id in $rds_instances; do
    arn=$(aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$id" --query 'DBInstances[0].DBInstanceArn' --output text)
    company=$(aws rds list-tags-for-resource --resource-name "$arn" --region "$REGION" --output json | jq -r '.TagList[] | select(.Key=="Company") | .Value')
    resource_name=$(aws rds list-tags-for-resource --resource-name "$arn" --region "$REGION" --output json | jq -r '.TagList[] | select(.Key=="Resource Name") | .Value')
    business_unit=$(aws rds list-tags-for-resource --resource-name "$arn" --region "$REGION" --output json | jq -r '.TagList[] | select(.Key=="Business Unit") | .Value')
    department=$(aws rds list-tags-for-resource --resource-name "$arn" --region "$REGION" --output json | jq -r '.TagList[] | select(.Key=="Department") | .Value')
    cost_center=$(aws rds list-tags-for-resource --resource-name "$arn" --region "$REGION" --output json | jq -r '.TagList[] | select(.Key=="CostCenter") | .Value')

    # Set empty values to blank
    if [[ -z "$company" ]]; then
        company=""
    fi
    if [[ -z "$business_unit" ]]; then
        business_unit=""
    fi
    if [[ -z "$department" ]]; then
        department=""
    fi
    if [[ -z "$cost_center" ]]; then
        cost_center=""
    fi

    # Determine if the resource is tagged based on Company, Department, and CostCenter
    if [[ -n "$company" && -n "$department" && -n "$cost_center" ]]; then
        is_tagged="Yes"
    else
        is_tagged="No"
    fi

    line=$(print_line "rds:db-instance" "$resource_name" "$id" "$company" "$business_unit" "$department" "$cost_center" "$is_tagged")
    echo "$line"
    RESULTS+=("$line")

    if [[ "$is_tagged" == "No" ]]; then
        UNTAGGED+=("$line")
    fi
done

# Save the results to a file
{
    echo "Rsource-Type   | Resource-Name    | Resource-ID           | Company      | Business-Unit   | Department  | CostCenter   | Tagged"
    echo "──────────────+────────────────+─────────────────────+─────────────+────────────+──────────+─────────────+──────────────+─────-"
    for line in "${RESULTS[@]}"; do
        echo "$line"
    done
} > "$OUTPUT_FILE"

echo
echo "Saved results to: $OUTPUT_FILE"

## Upload to S3
if ! aws s3 ls "s3://${S3_BUCKET}" --region "$REGION" >/dev/null 2>&1; then
    echo "Creating bucket: $S3_BUCKET"
    aws s3 mb "s3://${S3_BUCKET}" --region "$REGION"
fi

aws s3 cp "$OUTPUT_FILE" "s3://${S3_BUCKET}/$OUTPUT_FILE" --region "$REGION"
echo "Uploaded to S3: s3://${S3_BUCKET}/$OUTPUT_FILE"

# Send SNS only if untagged resources exist
if [[ ${#UNTAGGED[@]} -gt 0 ]]; then
    echo "Untagged resources found. Sending SNS notification..."

    sns_message=$(
        printf "Untagged resources found in %s:\n\n" "$OUTPUT_FILE"
        printf "Rsource-Type   | Resource-Name    | Resource-ID           | Company      | Business-Unit   | Department  | CostCenter\n"
        printf "──────────────+────────────────+─────────────────────+─────────────+────────────+──────────+───────────-+───────────-\n"
        for line in "${UNTAGGED[@]}"; do
            echo "$line" | cut -d'|' -f1-7
        done
    )

    aws sns publish \
        --region "$REGION" \
        --topic-arn "$SNS_TOPIC_ARN" \
        --subject "AWS Tag Audit Alert - Untagged Resources Found" \
        --message "$sns_message"

else
    echo "All resources are tagged. No SNS alert sent."
fi
