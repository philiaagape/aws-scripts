#!/bin/bash

VAULT_LIST=./aws-vaults.txt

######################################################
# read args, print usage if needed
######################################################
function usage() {
  cat<<ENDUSAGE
Usage: $(basename $0) [-h] [--skip-inventory] vaultname

Description: For given vaultname, check if it is a valid vault name based on
    the file $VAULT_LIST

    If $VAULT_LIST doesn't exist, generate it.

    If an inventory of vaultname hasn't been performed then run the inventory
    job and wait for it to complete.

    If --skip-inventory is used, attempt to use an existing inventory file like
    vaultname-archiveids.txt or if not found, then print error and exit.

    Use inventory file containing list of archive IDs to delete each archiveid
    from the vault, one at a time.

    After deletion of all archives, run another inventory job that should
    return empty. Print the contents for verification.

    Once it is verified empty, run the delete command on the given vaultname

Options:
  -h|--help          Print this usage and exit
  --skip-inventory   Skip the first inventory job step.
                     Use this if you have the archive IDs already and just 
                     want to start deleting them.
ENDUSAGE
}

[ $# -eq 0 ] && { usage; exit 1; }

SKIP_INVENTORY=0
while [ $# -gt 0 ]; do
  case $1 in
    -h|--help)  usage; exit; ;;
    --skip-inventory) SKIP_INVENTORY=1; ;;
    -*) echo "ERROR: unknown option $1"; usage; exit 1; ;;
    *) vault_name=$1; ;;
  esac
  shift
done

######################################################
# sanity checks
######################################################
#if there is no VAULT_LIST file, generate it
if [ ! -r $VAULT_LIST ]; then
    echo "WARNING: no vault list file $VAULT_LIST found."
    echo "Will run this command to generate it:"
    echo "aws glacier list-vaults --account-id - | awk -F\" '/VaultName/ {print $4}' \> $VAULT_LIST"
    read -p "Continue? [Y|n]: " continue_yes_or_no
    [ "$continue_yes_or_no" = "n" ] && exit
    aws glacier list-vaults --account-id - | awk -F\" '/VaultName/ {print $4}' > $VAULT_LIST
fi
# can't continue if the vault name is invalid
grep -q "$vault_name" $VAULT_LIST || { echo "ERROR: invalid vault_name"; exit 1; }

######################################################
# Main
######################################################
echo "working on vault: $vault_name"

if [ $SKIP_INVENTORY -eq 1 ]; then
  if [ -f ${vault_name}-archiveids.txt ]; then
    echo "skipping inventory job, using existing file"
  else
    echo "ERROR: no existing inventory file found like this"
    echo "${vault_name}-archiveids.txt"
    echo "Run this again without the --skip-inventory"
  fi
else
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
fi

echo "number of archive IDs to delete: $(cat ${vault_name}-archiveids.txt | wc -l)"

######################################################
# main work - delete the archives in the current vault
######################################################
cat ${vault_name}-archiveids.txt | while read theid; do 
  #print the number of the current archive ID on screen
  echo -n "$(tput cup $(tput lines) 0)$(grep -n "$theid" ${vault_name}-archiveids.txt | awk -F: '{print $1}')" >&2
  aws glacier delete-archive --account-id - --vault-name $vault_name --archive-id \"$theid\"
done

######################################################
# it isn't clear if this is necessary, but we may need to run
# the inventory job again so that we can verify that it is empty
# before we can finally delete the vault
######################################################
echo "running another inventory job to verify that $vault_name is empty"
aws glacier initiate-job --account-id - --vault-name $vault_name --job-parameters '{"Type": "inventory-retrieval"}' > ${vault_name}-inventory-jobid
inventory_jobid=$(awk -F\" '/jobId/ {print $4}' ${vault_name}-inventory-jobid)
is_done=$(aws glacier describe-job --account-id - --vault-name $vault_name --job-id $inventory_jobid | awk '/Completed/ {print $NF}')
minutes=0
while [ "$is_done" = "false," ]; do 
  sleep 300
  is_done=$(aws glacier describe-job --account-id - --vault-name $vault_name --job-id $inventory_jobid | awk '/Completed/ {print $NF}')
  echo "waited $((minutes+=5)) minutes"
done
aws glacier get-job-output --account-id - --vault-name $vault_name --job-id $inventory_jobid ${vault_name}-should-be-empty.json
echo "inventory job done"
echo ""

echo "check the file ${vault_name}-should-be-empty.json -  it should be empty so that we can delete the vault"
echo "printing the contents of the file now:"
cat ${vault_name}-should-be-empty.json
read -p "is the above file empty so we can proceed? [Y|n] (Ctrl-C to quit, default is yes): " yes_or_no

[ "$yes_or_no" = "n" ] && exit

######################################################
# yay! delete it!
######################################################
aws glacier delete-vault --vault-name $vault_name --account-id -

#comment out this vault and work on the next one
sed -i "s/$vault_name/#$vault_name/" $VAULT_LIST

echo "done with vault: $vault_name"
