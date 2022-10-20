#!/bin/bash
######################################################
# prep
######################################################
aws glacier list-vaults --account-id - > aws-vaults.json
#get just the vault names
awk -F\" '/VaultName/ {print $4}' aws-vaults.json  > aws-vaults.txt

######################################################
# start of main loop for current vault (first one that isn't commented)
# we can't delete a vault while there are archives in it
# so we have to delete those first
######################################################
while [ $(grep "^[^#]" aws-vaults.txt | wc -l) -gt 0 ]; do

#get the vault name
vault_name=$(grep "^[^#]" aws-vaults.txt | head -n1)

echo "working on vault: $vault_name"

#run an inventory job on this vault to get the archive IDs
aws glacier initiate-job --account-id - --vault-name $vault_name --job-parameters '{"Type": "inventory-retrieval"}' > ${vault_name}-inventory-jobid
inventory_jobid=$(awk -F\" '/jobId/ {print $4}' ${vault_name}-inventory-jobid)
#check if it is done... this takes several hours, so just keep checking once every 5 minutes
is_done=$(aws glacier describe-job --account-id - --vault-name $vault_name --job-id $inventory_jobid | awk '/Completed/ {print $NF}')
minutes=0
while [ "$is_done" = "false," ]; do 
  sleep 300
  is_done=$(aws glacier describe-job --account-id - --vault-name $vault_name --job-id $inventory_jobid | awk '/Completed/ {print $NF}')
  echo "waited $((minutes+=5)) minutes"
done
#get the inventory job results
aws glacier get-job-output --account-id - --vault-name $vault_name --job-id $inventory_jobid ${vault_name}.json

#clean up the job results so we have just the archive IDs
sed -e 's/\"ArchiveList\":\[//' -e 's/,/\n/g' $vault_name.json | awk -F\" '/ArchiveId/ {print $4}' > ${vault_name}-archiveids.txt
echo "done generating inventory of archive IDs for vault $vault_name"

echo "number of archive IDs to delete: $(cat ${vault_name}-archiveids.txt | wc -l)"

######################################################
# main work - delete the archives in the current vault
######################################################
cat ${vault_name}-archiveids.txt | while read theid; do 
  #print the number of the current archive ID on screen
  echo -n "$(tput cup $(tput lines) 0)$(grep -n "$theid" ${vault_name}-archiveids.txt | awk -F: '{print $1}')" >&2
  aws glacier delete-archive --account-id - --vault-name $vault_name --archive-id=\"$theid\"
done

######################################################
# it isn't clear if this is necessary, but we may need to run
# the inventory job again so that we can verify that it is empty
# before we can finally delete the vault
######################################################
aws glacier initiate-job --account-id - --vault-name $vault_name --job-parameters '{"Type": "inventory-retrieval"}' > ${vault_name}-inventory-jobid
inventory_jobid=$(awk -F\" '/jobId/ {print $4}' ${vault_name}-inventory-jobid)
#check if it is done... this takes several hours, so just keep checking once every 5 minutes
is_done=$(aws glacier describe-job --account-id - --vault-name $vault_name --job-id $inventory_jobid | awk '/Completed/ {print $NF}')
minutes=0
while [ "$is_done" = "false," ]; do 
  sleep 300
  is_done=$(aws glacier describe-job --account-id - --vault-name $vault_name --job-id $inventory_jobid | awk '/Completed/ {print $NF}')
  echo "waited $((minutes+=5)) minutes"
done
#get the inventory job results
aws glacier get-job-output --account-id - --vault-name $vault_name --job-id $inventory_jobid ${vault_name}.json

echo "check the file ${vault_name}.json -  it should be empty so that we can delete the vault"
echo "printing the contents of the file now:"
cat ${vault_name}.json
read -p "is the above file empty so we can proceed? [Y|n] (Ctrl-C to quit, default is yes): " yes_or_no

[ "$yes_or_no" = "n" ] && exit

######################################################
# yay! delete it!
######################################################
aws glacier delete-vault --vault-name $vault_name --account-id -

#comment out this vault and work on the next one
sed -i "s/$vault_name/#$vault_name/" aws-vaults.txt

echo "done with vault: $vault_name"
#end the while loop
done
