# 环境变量设置-二进制及库文件
alias rm='rm'
alias mv='mv'
alias cp='cp'

#git
GIT_EXEC_PATH=/opt/bin/git-core
PATH=$PATH:/opt/bin:/tmp/bin
GITPERLLIB=/opt/lib/perl
LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/opt/lib

export GIT_EXEC_PATH PATH GITPERLLIB LD_LIBRARY_PATH
export HOME=/tmp/
