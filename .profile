# 环境变量设置-二进制及库文件
alias rm='rm'
alias mv='mv'
alias cp='cp'

#git
GIT_EXEC_PATH=/opt/bin/git-core
PATH=/opt/bin:/tmp/bin:$PATH
GITPERLLIB=/opt/lib/perl
LD_LIBRARY_PATH=/opt/lib:$LD_LIBRARY_PATH

export GIT_EXEC_PATH PATH GITPERLLIB LD_LIBRARY_PATH
export HOME=/tmp/

export LANGUAGE=zh_CN.UTF-8
export LANG=zh_CN.UTF-8
export LC_CTYPE=zh_CN.UTF-8
export LC_COLLATE=zh_CN.UTF-8
export LC_IDENTIFICATION=zh_CN.UTF-8
export LC_ALL=zh_CN.UTF-8