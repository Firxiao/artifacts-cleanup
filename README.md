# artifacts-cleanup

This project is used to manage the cleanup jobs for Artifactory.

# usage

## set credentials in _~/.cleanup_

```
user=xxx
password=xxx"
```

## clone project

```
git clone https://github.com/firxiao/artifacts-cleanup.git
```

## setup rules file

rule example:

```
# cluster   repo               path       relative_date   dryrun
cluster01   generic-local  test       5d               True
```

## run

```
cd artifacts-cleanup
./cleanup.sh rules_file
```

## debug

logs is under _logs/_.
