# aws-scripts

Reference: https://docs.aws.amazon.com/amazonglacier/latest/dev/deleting-vaults-cli.html

You can only delete a vault when it is empty. So you must first get an inventory of the vault, then delete all the individual archives contained in the vault, then get another inventory to confirm the vault is empty. Finally, you can delete the vault.

Essential steps:

aws glacier list-vaults --account-id -
 * get a list of vaults
aws glacier initiate-job --account-id - --vault-name $VAULTNAME --job-parameters '{"Type": "inventory-retrieval"}'
 * wait for the inventory job to complete, takes several hours
 * get jobId from output of the above command
aws glacier describe-job --account-id - --vault-name $VAULTNAME --job-id $JOBID
 * inventory job is done when this returns "Completed": true,
aws glacier get-job-output --account-id - --vault-name $VAULTNAME --job-id $JOBID output.json
 * get ArchiveID from above output.json
aws glacier delete-archive --account-id - --vault-name $VAULTNAME --archive-id "$ARCHIVEID"
 * repeat this for each ArchiveID in output.json
aws glacier initiate-job --vault-name awsexamplevault --account-id 111122223333 --job-parameters '{"Type": "inventory-retrieval"}'
 * wait for this second inventory job to finish to confirm the vault is empty
aws glacier delete-vault --account-id - --vault-name $VAULTNAME
 * this will only work if the vault is empty

## 1) install awscli from here:

https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

## 2) create ~/.aws/credentials file with contents like this:
```
[default]
aws_access_key_id = paste access key here
aws_secret_access_key = paste secret key here
```

## 3) create ~/.aws/config file with contents like this:
```
[default]
account-id = paste account id here
region = paste your region here
output = json
```
Once you've got the account-id saved here, you can run aws CLI commands with "--account-id -" to have it use the saved account-id value.

## 4) then you can run the custom shell scripts:
```
aws-delete-vault.sh vaultname
aws-delete-all-vaults.sh
```

## 5) if you don't know the name(s) of your vault(s), run these commands:
```
aws glacier list-vaults --account-id - > aws-vaults.json
awk -F\" '/VaultName/ {print $4}' aws-vaults.json  > aws-vaults.txt
```
