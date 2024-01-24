### Wanted to create an EC2 in any account that would self destruct in case I forgot to come clean it up.
In case you're wondering, this is used when spinning up a new account and wanting to verify my automations against EC2s work, and there are no EC2s yet in that account.

Assumes you're auth'd to a given account, and have EC2 creation permissions

### Usage:

```bash
➜ launch_test_ec2_instance 2                                                    
Instance ID: i-123456789
Expected Termination Time: 2024-01-23 14:48

➜ launch_test_ec2_instance                                                
Instance ID: i-789456123
Expected Termination Time: 2024-01-23 15:45
```

### Drop this in your `~/.zshrc`

```bash
launch_test_ec2_instance() {

  local suicide_time=${1:-55}
  local image_id=$(aws ec2 describe-images --owners amazon --filters "Name=name,Values=amzn2-ami-kernel-*-x86_64-gp2" --query 'sort_by(Images, &CreationDate)[0].ImageId' --output text)
  local subnet_id=$(aws ec2 describe-subnets --query 'Subnets[0].SubnetId' --output text)
  local user_data=$(echo -e '#!/bin/bash\n\necho "sudo halt" | at now + '$suicide_time 'minutes')

  local instance_id=$(aws ec2 run-instances \
    --image-id "$image_id" \
    --instance-type t2.micro \
    --subnet-id "$subnet_id" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value='$(whoami)-test'},{Key=PatchGroup,Value=default}]' \
    --instance-initiated-shutdown-behavior terminate \
    --metadata-options HttpEndpoint=enabled,HttpTokens=required \
    --instance-market-options '{"MarketType": "spot", "SpotOptions": {"MaxPrice": "0.1", "SpotInstanceType": "one-time"}}' \
    --user-data "$user_data" \
    --query 'Instances[0].InstanceId' \
    --output text
  )

  local termination_time=$(date -d "+$suicide_time minutes" '+%Y-%m-%d %H:%M')

  echo "Instance ID: $instance_id"
  echo "Expected Termination Time: $termination_time"
}
```