
---
>纯shell脚本，对clash订阅链接进行可用性检测，并按照代理节点按照地域重命名
>可用 Github Actions 一键部署到远程VPS服务器或者腾讯云函数
---

# 部署说明

## 第一步 Github环境变量设置

申请一个Personal access token，授予repo和workflow权限

在本项目settings->Actions secrets新建几个 **Actions secrets** 如下, 并填入相关参数：

```bash
# ******** 必须 ********
TC_GH_TOKEN		# github密钥 (将上面申请到的Personal access token粘贴进来即可)
TC_POOL_URL		# 代理池URL地址，仅支持clash yaml格式 (必须)

# ******** 如果需要部署到腾讯云函数 ********
TC_SECRET_ID		# 腾讯云SECRET_ID（）
TC_SECRET_KEY		# 腾讯云SECRET_KEY（如果需要部署到腾讯云函数）

# ******** 如果需要部署到远程服务器 ********
REMOTE_IP		#目标VPS的IP地址或者指向的域名
REMOTE_PORT		#ssh端口
REMOTE_SSH_KEY		#ssh密钥 (密钥与密码二选一即可)
REMOTE_PASSWORD		#ssh登录密码 (密钥与密码二选一即可)
REMOTE_USER_NAME	#ssh登录用户名	

``` 

[代理池URL测试地址1](https://raw.githubusercontent.com/hansyao/pool_checker/master/subscribe/pool_no_cn_verified.yaml)

[代理池URL测试地址2](https://proxy.yugogo.xyz/clash/proxies)

强烈建议按照[教程](../zu1k/proxypool)自己搭建一个爬虫代理池。



## 第二步 运行Actions

**直接Github Actions运行:** 

运行Action[代理池验证](./pool_checker/actions/workflows/main.yml) , 默认每6小时运行一次，可按需更改[main.yml](./pool_checker/blob/e59833352b7f5921aeb3dddd6a09bba3fffe89eb/.github/workflows/main.yml#L5)中的cron为自定义运行时间。

**部署到远程服务器VPS:** 

手工运行Action[部署到远程服务器](./pool_checker/actions/workflows/deploy_to_remote.yml)即可，本项目会自动提交到你在[第一步](#第一步-Github环境变量设置)中指定的服务器, 并设定计划任务(默认每小时一次, 可按需修改[deploy_to_remote.sh](./blob/5e28ca8215b7260e223c0a75ca6a63a311d69ac9/deploy_to_remote.sh#L119))或者在你的远程服务器上更改crob job. 运行完成后的订阅结果会自动反向提交到你的github仓库[Actions/subscribe](./tree/master/Actions/subscribe)文件夹里。

**部署到腾讯云函数:** 

手工运行Action[部署到腾讯云函数](./pool_checker/actions/workflows/tencent_cloud.yml)即可，本项目会自动为你在你的腾讯账户中创建一个名称为pool_checker的云函数，并设置一个timer类型默认每2小时运行一次的自动任务。可按需更改[tencent_cloud.yml](./pool_checker/blob/bf5b08d4de5dda3b0e668582592f928f0d2d8bfd/.github/workflows/tencent_cloud.yml#L42)为自定义参数，或者直接在腾讯云函数后台中按需更改。运行完成后的订阅结果会自动反向提交到你的github仓库[Actions/subscribe](./tree/master/Actions/subscribe)文件夹里。

如有代码更新， 重新运行一下Action即可，你的远程VPS服务器或者腾讯云函数的代码也会相应得到更新。

