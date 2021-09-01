#!/bin/bash

TOKEN="${GH_TOKEN}"
REPO='hub.fastgit.org/hansyao'
APP='breakwall'

echo -e "从github克隆仓库"

cp -r `pwd`/share/git-core /tmp/
git config --global http.lowSpeedLimit 100
git config --global http.lowSpeedTime 60
git config --global init.templateDir /tmp/git-core/templates
git config --global protocol.https.allow always
git config --global init.defaultBranch master

cd /tmp/
if [[ ! -d ${APP} ]]; then
    mkdir breakwall
fi
cd breakwall
git init
git config core.sparsecheckout true
git config --local pull.rebase false
git config --local user.name "${GH_USER}"
git config --local user.email "${GH_EMAIL}"
git config --local --unset http.proxy


mkdir -p .git/info
git remote add origin https://${TOKEN}@${REPO}/${APP}.git
echo Actions/subscribe > .git/info/sparse-checkout
git pull --depth 1 origin master

# 判断爬取节点配置文件是否为空
for arg; do
    if [[ ! -z $(cat "$arg" | grep -E 'The following link|No nodes were found') ]]; then
        echo -e "节点配置文件"$arg"没有找到有效节点"
        continue
    fi
    cp -f "$arg" /tmp/${APP}/Actions/subscribe/ 
done

git add -f Actions/subscribe/
git commit -m "订阅更新-VERIFIED FROM CHINA ONLY"
git push "https://${TOKEN}@${REPO}/${APP}"

cd ${USER_CODE_ROOT}

echo -e "结束远程同步github仓库"
