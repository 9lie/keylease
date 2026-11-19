---
name: keylease
description: Use when the user needs to give the agent a secret, API key, token, or credential without pasting it into chat, or when a command needs a secret via Keylease. Guides the user to copy the secret to the clipboard and open a temporary Keylease channel, then injects the secret into a child process with `keylease run --env NAME -- command`. Never ask the user to paste the secret into the conversation.
---

# Keylease

Keylease 给 Agent 开一条**临时密钥通道**。通道是临时的，密钥本身不一定是临时的：用户可能只是不想让密钥进入聊天上下文，之后仍可能要求你把它保存到某个地方。

App 在 `/Applications/Keylease.app`，CLI 在 `/usr/local/bin/keylease`。

## 什么时候用

- 用户需要给你 API key、token、密码、私钥，或任何不能直接发到聊天里的凭证。
- 某条命令需要读取一个密钥，但你不应该把密钥值写进上下文、日志或命令参数。
- 用户说“我给你一个 key”“用这个 token 跑一下”“不要让我把密钥发给你”。

## 标准流程

1. 先检查通道是否已经开着：

```bash
keylease run --env <ENV_NAME> -- <command>
```

如果返回 `No active channel`，**不要停下来等用户回复**，直接改成等待模式再跑一次：

```bash
keylease run --wait --env <ENV_NAME> -- <command>
```

它会在后台阻塞，最长默认 10 分钟；用户把密钥复制到剪贴板并开启通道后，命令会立刻自动执行，用户不需要再发消息说“好了”。

2. 第一次需要用户开启通道时，用这段中文提醒，不要要求用户把密钥发给你：

> 请把密钥复制到剪贴板，然后点菜单栏的钥匙图标（或按 `⇧⌘K`），再点「从剪贴板开启通道」。不用把密钥发给我。

如果用户找不到图标：

```bash
open /Applications/Keylease.app
keylease show
```

3. 命令会自动在通道开启后执行。不要追问密钥内容，也不要要求用户确认密钥值，更不要再提醒“开好了告诉我”。

如果当前工具对单次调用有超时限制，用 `--timeout 2m` 缩短单次等待，超时后再调用一次 `keylease run --wait ...` 继续等；不要改成反复询问用户。

## 变量名由你指定

`--env` 后面的变量名由 Agent 根据目标工具决定，不需要用户命名。常见例子：

```bash
keylease run --env OPENAI_API_KEY -- python app.py
keylease run --env GITHUB_TOKEN -- gh pr list
keylease run --env ANTHROPIC_API_KEY -- claude ...
keylease run --env AWS_SECRET_ACCESS_KEY -- aws ...
```

不传 `--env` 时默认注入 `KEYLEASE_SECRET`。

只想等通道开启、暂时不执行命令时：

```bash
keylease wait --timeout 10m
```

它成功返回 0 表示通道已开启；超时会返回非 0。

如果工具需要多个变量，用 shell 做映射：

```bash
keylease run --env KEYLEASE_SECRET -- sh -c 'OPENAI_API_KEY=$KEYLEASE_SECRET exec python app.py'
```

注意 Keylease 同一时间只保存一把密钥。需要多个不同的密钥时，请让用户分别开通道，或改用用户指定的密钥管理方式。

## 通道规则

- 默认有效期 10 分钟。
- 只能使用 1 次：每调用一次 `keylease run` 就消费掉通道。
- 因为只有一次机会，**把需要密钥的多个步骤合并进同一条命令或同一个脚本**，不要先跑一次再跑第二次。
- App 退出后通道也立即关闭。
- 用户可以用菜单栏面板或 `keylease revoke` 立即关闭。

如果通道过期或已经被使用，再提醒用户复制密钥并重新开启。

## 不要做

- 不要要求用户把密钥贴进聊天。
- 不要用 `keylease set`，除非用户明确要求从 stdin/脚本设置；日常流程是菜单栏按钮。
- 不要执行 `echo $OPENAI_API_KEY`、`printenv`、`env`、`cat` 之类的命令来“确认”密钥。
- 不要把密钥写入日志、提交、issue、PR、聊天消息或无关的网络请求。
- 不要把密钥值拼进命令行参数；让工具从环境变量读。
- 不要因为输出里出现 `[REDACTED]` 就认为失败；这是正常的脱敏结果。

## 保存密钥

用户如果明确要求“把这个密钥存到某处”，可以在通道有效期内用该密钥完成写入，例如写入用户指定的配置文件、密码管理器或 CI secret。通道关闭不等于密钥必须被丢弃；是否长期保存由用户决定。保存后不要在聊天里回显密钥。

## 边界

这不是防恶意 Agent 的硬边界：同一用户的进程仍可以调用 `keylease run` 并尝试把值编码出来。它防的是密钥误进聊天、日志、命令历史和模型上下文。需要更强隔离时，提醒用户使用每次确认、命令白名单或专用密钥管理服务。
