#!/usr/bin/env bash

debug() {
    if [[ "$DEBUG" ]]; then
       echo "===> [${FUNCNAME[1]}] $*" 1>&2
    fi
}
_run() {
    if [[ "$DRY" ]]; then
      debug '---> DRY-RUN'
      echo "$@" | sed 's/ -/ \\\n -/g'
    else 
      "$@"
    fi
}

amis() {
  open https://cloud-images.ubuntu.com/locator/ec2/
}

types() {
  declare desc="List Instancetype for SPOT with memory size limits"
  declare minMem=${1:-5000} maxMem=${2:-10000}

  _run aws ec2 describe-instance-types \
   --query "
   InstanceTypes[? 
     contains(SupportedUsageClasses, \`spot\`) 
     && MemoryInfo.SizeInMiB < \`${maxMem}\` 
     && MemoryInfo.SizeInMiB > \`${minMem}\`] 
     | sort_by(@, &MemoryInfo.SizeInMiB) 
     | [].[MemoryInfo.SizeInMiB, InstanceType]
   " 
}

create-stack() {
  _run aws cloudformation create-stack \
    --stack-name bbb-$(date +%H%M) \
    --template-body file://cloudformation.yaml \
    --parameters \
      ParameterKey=KeyName,ParameterValue=id_rsa_lly \
      ParameterKey=NodeSpotPrice,ParameterValue=0.1 \
      ParameterKey=AWSManagedDomain,ParameterValue=true \
      ParameterKey=HostName,ParameterValue=maradjotthon \
      ParameterKey=DomainName,ParameterValue=hatnem.de \
      ParameterKey=VPC,ParameterValue=vpc-bf9373d6
}

create-custom-stack() {
  _run aws cloudformation create-stack \
    --capabilities CAPABILITY_IAM \
    --stack-name custom-$(date +%H%M) \
    --template-body file://custom-res.yaml
}


main() {
  : ${DEBUG:=1}
  
  # if last arg is --dry sets DRY=1
  [[ ${@:$#} =~ --dry ]] && { set -- "${@:1:$(($#-1))}" ; DRY=1 ; } || :

  if [[ $1 =~ :: ]]; then 
    debug DIRECT-COMMAND  ...
    command=${1#::}
    shift
    $command "$@"
  else 
    types "$@"
  fi 
  ##[[ "$DRY" ]] || reset
}

[[ "$0" == "$BASH_SOURCE" ]] && main "$@" || true
