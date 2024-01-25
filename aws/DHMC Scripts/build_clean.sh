#!/bin/bash
set -x
# Define your AWS region
AWS_REGION="us-east-1"
CHANGE_POLICIES_FILE="change_policies.sh"

# Clear the existing change_policies.sh file
> $CHANGE_POLICIES_FILE

# Initialize variables to store information for each block
INSTANCE_NAME=""
INSTANCE_ID=""
IAM_ROLE=""
POLICY_NAME=""

# Loop through each entry in actual_policies.txt
while IFS= read -r line; do
    # Check if the line is empty (indicating the end of a block)
    if [ -z "$line" ]; then
        # Check if the policy contains "Amazon"
        if [[ "$POLICY_NAME" == *"Amazon"* ]]; then
            # Generate AWS CLI command to delete the policy from the role
            echo "aws iam delete-role-policy --region $AWS_REGION --role-name $IAM_ROLE --policy-name $POLICY_NAME" >> $CHANGE_POLICIES_FILE
        else
            # Generate AWS CLI command to modify the policy
            echo "aws iam get-role-policy --region $AWS_REGION --role-name $IAM_ROLE --policy-name $POLICY_NAME --output text --query 'PolicyDocument' | jq 'del(.Statement[] | select(.Action | contains(\"ssm:\")) | .Action) | del(.Statement[] | select(.Action | contains(\"ssm:UpdateInstanceInformation\")) | .Action)' | aws iam put-role-policy --region $AWS_REGION --role-name $IAM_ROLE --policy-name $POLICY_NAME --policy-document file:///dev/stdin" >> $CHANGE_POLICIES_FILE
        fi

        # Reset variables for the next block
        INSTANCE_NAME=""
        INSTANCE_ID=""
        IAM_ROLE=""
        POLICY_NAME=""
    else
        # Parse the information from the line
        case "$line" in
            *"Instance Name: "*) INSTANCE_NAME=${line#*Instance Name: } ;;
            *"Instance ID: "*) INSTANCE_ID=${line#*Instance ID: } ;;
            *"IAM Role: "*) IAM_ROLE=${line#*IAM Role: } ;;
            *"Policy: "*) POLICY_NAME=${line#*Policy: } ;;
        esac
    fi
done < actual_policies.txt

# Make the script executable
# chmod +x $CHANGE_POLICIES_FILE

echo "Change policies script generated: $CHANGE_POLICIES_FILE"
