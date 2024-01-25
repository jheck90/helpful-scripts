#!/bin/bash

# Define your AWS region
AWS_REGION="us-east-1"
OUTPUT_FILE="findings.txt"
ACTUAL_POLICIES_FILE="actual_policies.txt"
CHANGE_POLICIES_FILE="change_policies.sh"



# Function to add a delay between API calls
function api_call {
    sleep 1  # Adjust this delay as needed
}

# Clear the existing findings and policies files
> $OUTPUT_FILE
> $ACTUAL_POLICIES_FILE
> $CHANGE_POLICIES_FILE

# Enable debug mode
set -x

# Get the AWS account ID from the credentials
ACCOUNT_ID=$(aws sts get-caller-identity --region $AWS_REGION --query 'Account' --output text)

# Get a list of all running instances
RUNNING_INSTANCES=$(aws ec2 describe-instances --region $AWS_REGION --filters Name=instance-state-name,Values=running --query 'Reservations[*].Instances[*].[InstanceId]' --output text)

# Initialize a variable to store the last processed IAM role
LAST_IAM_ROLE=""

# Get the total number of running instances
TOTAL_INSTANCES=$(echo "$RUNNING_INSTANCES" | wc -w)

# Initialize a counter variable
INSTANCE_COUNTER=0

# Output running instances to findings.txt
echo "Running Instances:" >> $OUTPUT_FILE
echo "$RUNNING_INSTANCES" >> $OUTPUT_FILE
echo "" >> $OUTPUT_FILE


# Loop through each running instance
for INSTANCE_ID in $RUNNING_INSTANCES; do
    # Increment the instance counter
    ((INSTANCE_COUNTER++))
    # Get the IAM instance profile associated with the instance
    IAM_INSTANCE_PROFILE=$(aws ec2 describe-instances --region $AWS_REGION --instance-ids $INSTANCE_ID --query 'Reservations[*].Instances[*].IamInstanceProfile.Arn' --output text)
    # Get the instance name based on its ID
    INSTANCE_NAME=$(aws ec2 describe-instances --region $AWS_REGION --instance-ids $INSTANCE_ID --query 'Reservations[*].Instances[*].Tags[?Key==`Name`].Value' --output text)
    
    # Output IAM instance profile list to findings.txt
    echo "IAM Instance Profile:" >> $OUTPUT_FILE
    echo "$IAM_INSTANCE_PROFILE" >> $OUTPUT_FILE

    # Output instance name to findings.txt
    echo "Instance Name: $INSTANCE_NAME" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE

    echo "" >> $OUTPUT_FILE

    # Get the IAM role attached to the instance profile
    IAM_ROLE=$(aws iam get-instance-profile --region $AWS_REGION --instance-profile-name $(basename $IAM_INSTANCE_PROFILE) --query 'InstanceProfile.Roles[*].RoleName' --output text)

    # Output instance count information
    echo "Instance $INSTANCE_COUNTER of $TOTAL_INSTANCES:" >> $OUTPUT_FILE

    # Check if the current IAM role is the same as the last processed IAM role
    if [ "$IAM_ROLE" == "$LAST_IAM_ROLE" ]; then
        echo "$INSTANCE_NAME using already listed role of $IAM_ROLE" >> $OUTPUT_FILE
        echo "" >> $OUTPUT_FILE
        continue  # Skip to the next iteration of the loop
    fi
   

    # Output IAM role to findings.txt
    echo "IAM Role: $IAM_ROLE" >> $OUTPUT_FILE

    # Get the role's inline policies
    INLINE_POLICIES=$(aws iam list-role-policies --region $AWS_REGION --role-name $IAM_ROLE --query 'PolicyNames' --output text)

    # Output inline policies to findings.txt
    echo "Inline Policies:" >> $OUTPUT_FILE
    echo "$INLINE_POLICIES" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE

    # Loop through each inline policy
    for POLICY_NAME in $INLINE_POLICIES; do
        echo "Inline Policy: $POLICY_NAME" >> $OUTPUT_FILE

        # Get and output the policy document
        aws iam get-role-policy --region $AWS_REGION --role-name $IAM_ROLE --policy-name $POLICY_NAME --output text --query 'PolicyDocument' >> $OUTPUT_FILE

        echo "" >> $OUTPUT_FILE
    done

    # Get the role's attached policies with AWS Managed policies
    ATTACHED_POLICIES_AWS=$(aws iam list-attached-role-policies --region $AWS_REGION --role-name $IAM_ROLE --query 'AttachedPolicies[?contains(PolicyArn, `iam::aws:policy`)].PolicyArn' --output text)

    # Output attached AWS Managed policies to findings.txt
    echo "Attached Policies (AWS Managed):" >> $OUTPUT_FILE
    echo "$ATTACHED_POLICIES_AWS" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE

    # Get the role's attached policies without AWS Managed policies
    ATTACHED_POLICIES_USER=$(aws iam list-attached-role-policies --region $AWS_REGION --role-name $IAM_ROLE --query 'AttachedPolicies[?contains(PolicyArn, `iam::aws:policy`)==`false`].PolicyArn' --output text | tr -d '[]')

    # Output attached user-defined policies to findings.txt
    echo "Attached Policies (User Defined):" >> $OUTPUT_FILE
    echo "$ATTACHED_POLICIES_USER" >> $OUTPUT_FILE
    echo "" >> $OUTPUT_FILE

    # Combine all policies into a single list
    ALL_POLICIES=$(echo "$INLINE_POLICIES $ATTACHED_POLICIES_AWS $ATTACHED_POLICIES_USER" | tr ' ' '\n' | sort -u)
    # Check the contents of each policy for "ssm:*" or "ssm:UpdateInstanceInformation"
    for POLICY_ARN in $ALL_POLICIES; do
        POLICY_NAME=$(basename $POLICY_ARN)
        DEFAULT_VERSION_ID=$(aws iam get-policy --region $AWS_REGION --policy-arn $POLICY_ARN --query 'Policy.DefaultVersionId' --output text)

        if aws iam get-policy-version --region $AWS_REGION --policy-arn $POLICY_ARN --version-id $DEFAULT_VERSION_ID | grep -q 'ssm:\*\|ssm:UpdateInstanceInformation'; then
            echo "  $POLICY_NAME: true" >> $OUTPUT_FILE
            echo "Instance Name: $INSTANCE_NAME" >> $ACTUAL_POLICIES_FILE
            echo "Instance ID: $INSTANCE_ID" >> $ACTUAL_POLICIES_FILE
            echo "IAM Role: $IAM_ROLE" >> $ACTUAL_POLICIES_FILE
            echo "Policy: $POLICY_NAME" >> $ACTUAL_POLICIES_FILE
            echo "" >> $ACTUAL_POLICIES_FILE
        else
            echo "  $POLICY_NAME: false" >> $OUTPUT_FILE
        fi
    done

    echo "" >> $OUTPUT_FILE  # Add a newline between entries

    # Update the last processed IAM role
    LAST_IAM_ROLE="$IAM_ROLE"

    # Pause between API calls to avoid rate limits
    api_call
done

while IFS= read -r line; do
    # Parse the instance name, instance ID, IAM role, and policy name from the line
    INSTANCE_NAME=$(echo "$line" | grep -o 'Instance Name: .*' | cut -d' ' -f 3-)
    INSTANCE_ID=$(echo "$line" | grep -o 'Instance ID: .*' | cut -d' ' -f 3-)
    IAM_ROLE=$(echo "$line" | grep -o 'IAM Role: .*' | cut -d' ' -f 3-)
    POLICY_NAME=$(echo "$line" | grep -o 'Policy: .*' | cut -d' ' -f 3-)

    # Check if the policy is an AWS Managed policy
    if [[ "$POLICY_NAME" == "arn:aws:iam::aws:policy/"* ]]; then
        # Generate AWS CLI command to delete AWS Managed policy from the role
        echo "aws iam delete-role-policy --region $AWS_REGION --role-name $IAM_ROLE --policy-name $POLICY_NAME" >> $CHANGE_POLICIES_FILE
    else
        # Generate AWS CLI command to modify inline or user-managed policy
        echo "aws iam get-role-policy --region $AWS_REGION --role-name $IAM_ROLE --policy-name $POLICY_NAME --output text --query 'PolicyDocument' | jq 'del(.Statement[] | select(.Action | contains(\"ssm:\")) | .Action) | del(.Statement[] | select(.Action | contains(\"ssm:UpdateInstanceInformation\")) | .Action)' | aws iam put-role-policy --region $AWS_REGION --role-name $IAM_ROLE --policy-name $POLICY_NAME --policy-document file:///dev/stdin" >> $CHANGE_POLICIES_FILE
    fi
done < $ACTUAL_POLICIES_FILE

echo "Change policies script generated: $CHANGE_POLICIES_FILE"

# Disable debug mode
set +x
