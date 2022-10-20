# aws-scripts
1) install awscli from here:

https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

2) create ~/.aws/credentials file with contents like this:

[default]
aws_access_key_id = paste access key here
aws_secret_access_key = paste secret key here

3) create ~/.aws/config file with contents like this:

[default]
account-id = paste account id here
region = paste your region here
output = json

4) then you can run the custom shell scripts:

aws-delete-vault.sh vaultname
aws-delete-all-vaults.sh

5) if you don't know the name(s) of your vault(s), run these commands:

aws glacier list-vaults --account-id - > aws-vaults.json
awk -F\" '/VaultName/ {print $4}' aws-vaults.json  > aws-vaults.txt
