# gitlab-server-job
Run salt states or commands on servers via Salt or SSH inside GitLab pipeline jobs, multiple Salt Masters with failover supported.

# Usage

## Inside Pipelines
Should be added as git submodule for Salt Master repo with .gitlab-ci.yml pipeline e.g. https://github.com/sysadmws/salt-project-template .
```
git submodule add --name .gitlab-server-job -b master -- https://github.com/sysadmws/gitlab-server-job .gitlab-server-job
```
Salt Masters should be gitlab-runners for Gitlab Project with Salt Master git repo.

[ci_sudo scripts](https://github.com/sysadmws/sysadmws-formula/tree/master/scripts/ci_sudo) from sysadmws-formula needed.

## Creating Pipelines
To run salt command `state.apply app.deploy` with salt timeout `300` for minion `srv1.xyz.tld` inside project `sysadmws/xyz-salt`:
```
pipeline_salt_cmd.sh sysadmws/xyz-salt 300 srv1.xyz.tld "state.apply app.deploy"
```

Running rsnapshot_backup examples (via salt, via ssh, via ssh with nonstd port):
```
pipeline_rsnapshot_backup.sh wait/nowait sysadmws/xyz-salt 300 srv1.xyz.tld SALT
pipeline_rsnapshot_backup.sh wait/nowait sysadmws/xyz-salt 300 srv1.xyz.tld SSH
pipeline_rsnapshot_backup.sh wait/nowait sysadmws/xyz-salt 300 srv1.xyz.tld SSH 1.2.3.4
pipeline_rsnapshot_backup.sh wait/nowait sysadmws/xyz-salt 300 srv1.xyz.tld SSH 1.2.3.4 2222
```

Env vars used:
- GL_URL - e.g. https://gitlab.xyz.tld
- GL_USER_PRIVATE_TOKEN - full access token of GitLab user with permissions to create git tags and pipelines

Custom Git Tag created before runnning pipeline to customize pipeline info about what is runnning - so errors and emails will contain info which command on which minion failed.
