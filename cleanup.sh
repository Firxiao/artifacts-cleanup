#!/usr/bin/env bash
#usage: cleanup repository with specified path

if [[ ! -e ~/.cleanup ]]; then
    echo "Please set user and password in ~/.cleanup
       user=xxx
       password=xxx"
       exit 1
else
    source ~/.cleanup
fi


if [[ $# != 1 ]] ; then
 echo "USAGE: $0 rules_file"
 echo " Eg: $0 cleanup_rules_test"
 echo "     cat cleanup_rules_test:
     # cluster                                   repo               path       relative_date   dryrun
     cluster01    generic-local  test       5d               True
    "
 exit 2;
fi

rules_file=$1


# Define log file
logpath=$(dirname $0)
[ -e "$logpath/logs" ] || mkdir "$logpath/logs"
logfile=$logpath/logs/$1-$(date +%Y%m%d).log

# Function: Setup logfile and redirect stdout/stderr.
log_setup() {
     # Check if logfile exists and is writable.
     ( [ -e "$logfile" ] || touch "$logfile" ) && [ ! -w "$logfile" ] && echo "ERROR: Cannot write to $logfile. Check permissions or sudo access." && exit 1

     tmplog=$(tail -n $logfile_max_lines $logfile 2>/dev/null) && echo "${tmplog}" > $logfile
     exec >  >(tee -a $logfile)
     exec 2>&1
}

log_setup

# Function: Log an event.
log() {
     echo "[$(date +"%Y-%m-%d"+"%T")]: $*"
}

function find_artifacts()
{
response=""
cleanable='False'
response=$(curl -s -u "$user:$password"  -X POST -H 'Content-Type:text/plain' --data \
'items.find({"repo":"'$repo'","$or":[
                {
                    "$and":[
                     {
                        "created":{"$before":"'${relative_date}'"},
                        "path": "'$path'"
                     }
                           ]
                }
                                                    ]
            }
            ).sort({"$desc" : ["updated"]})' $aql_api)

if [[ "$(echo $response|jq -r '.errors|.[].status' 2>/dev/null)x" == 401x ]]; then
    echo $response|jq -r '.errors|.[].message'
    exit 1
fi
if [[ "$(echo $response|jq -r '.range.total' 2>/dev/null)x" == 0x ]]; then
    log "no match found"
elif echo $response|jq -r '.results|.[]|.name' 2>&1 >/dev/null; then
    files=$(echo $response|jq -r '.results|.[]|.name')
    # DEBUG
    # echo $response
    num=$(echo $response|jq -r '.range.total')
    log "Found $num artifacts"
    if [[ "$dryrun" == "False" ]]; then
    	cleanable='True'
    else
        for file in $files; do
       	    echo "$file"
    	done
    fi
else
    log $response
fi
}

function delete_artifacts()
{
if [[ $cleanable == "True" ]]; then
    for file in $files
    do
        artifact="$base_url/$repo/$path/$file"
        log "Deleting $artifact"
        curl -s -u $user:$password  -X DELETE "$artifact"
    done
else
    echo ""
fi
}

function clean_trashcan()
{
  trashcan_api="https://artifactory-${cluster}01.example.org/api/trash/clean"
  # clean local trashcan
  log "Cleaning trashcan [$trashcan_api/$repo/$path]..."
  #curl -s -u $user:$password  -X DELETE "$trashcan_api/$repo/$path"
  # clean replica trashcan
  replica_repo=$(echo $repo|sed "s/-local/-artifactory-${cluster}01-replica/g")
  cluster01_trashcan_api="https://artifactory-cluster0101.example.org/api/trash/clean"
  cluster02_trashcan_api="https://artifactory-cluster0201.example.org/api/trash/clean"
  cluster03_trashcan_api="https://artifactory-cluster0301.example.org/api/trash/clean"
  case $cluster in
      cluster01)
        log "Cleaning trashcan [$cluster03_trashcan_api/$replica_repo/$path]..."
        curl -s -u $user:$password  -X DELETE "$cluster03_trashcan_api/$replica_repo/$path";
        log "Cleaning trashcan [$cluster02_trashcan_api/$replica_repo/$path]..."
        curl -s -u $user:$password  -X DELETE "$cluster02_trashcan_api/$replica_repo/$path";
        ;;
      cluster03)
        log "Cleaning trashcan [$cluster01_trashcan_api/$replica_repo/$path]..."
        curl -s -u $user:$password  -X DELETE "$cluster01_trashcan_api/$replica_repo/$path";
        log "Cleaning trashcan [$cluster02_trashcan_api/$replica_repo/$path]..."
        curl -s -u $user:$password  -X DELETE "$cluster02_trashcan_api/$replica_repo/$path";
        ;;
      cluster02)
        log "Cleaning trashcan [$cluster01_trashcan_api/$replica_repo/$path]..."
        curl -s -u $user:$password  -X DELETE "$cluster01_trashcan_api/$replica_repo/$path";
        log "Cleaning trashcan [$cluster03_trashcan_api/$replica_repo/$path]..."
        curl -s -u $user:$password  -X DELETE "$cluster03_trashcan_api/$replica_repo/$path";
        ;;
      *)
        log "There is no replica for cluster $cluster"  ;;
  esac


}



function main()
{

    cat $rules_file|awk '/^[^#]/'|while read rule; do
        cluster="$(echo $rule|awk '{print $1}')"
        case $cluster in
            cluster01) base_url="http://cluster01-artifactory:8081/artifactory" ;;
            cluster02) base_url="http://cluster02-artifactory:8081/artifactory" ;;
            cluster03) base_url="http://cluster03-artifactory:8081/artifactory" ;;
            test) base_url="http://cluster03-tst-artifactory:8081/artifactory" ;;
            *) echo -e "$cluster is not supprot, please check\n";exit 10 ;;
        esac
        repo="$(echo $rule|awk '{print $2}')"
        path="$(echo $rule|awk '{print $3}')"
        relative_date=$(echo $rule|awk '{print $4}')
        dryrun=$(echo $rule|awk '{print $5}')
        # api
        token_api="$base_url/api/security/token"
        aql_api="$base_url/api/search/aql"
        clean_trashcan
        echo ""
        if [[ $dryrun == False ]]; then
            log "Cleaning [$base_url/$repo/$path] artifacts before $relative_date ..."
            find_artifacts && delete_artifacts
	    else
       	    log "[Dryrun] Searching [$base_url/$repo/$path] artifacts before $relative_date ..."
            find_artifacts
	    fi
        done

}

main
