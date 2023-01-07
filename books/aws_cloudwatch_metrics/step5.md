---
title: "実践! AWSでログルーティング"
free: true
---

# はじめに
さて、ここで最初に示した画像に戻ってきました。
本章ではこれに従ってログルーティングを設定していきます。
![goal](/images/metrics/metric-sample.jpg)

今回は極力ログルーティングに関係のない話を控えるため、ECSへのデプロイの自動化などは取り扱いません。  
愚直に必要なイメージをECRに登録し、そのイメージを使ってECSを起動していきます。

サンプルコードはこちらです。
https://github.com/ange-k/metrics-sample

# DockerImage
RailsのDockerfileについては、ローカル環境と同様のものを使用できます。

しかし、FireLensログドライバが送ってくるログを扱うFluentBitについてはカスタマイズが必要になります。  
といっても、設定ファイルを追加するのみなので、Dockerfileはシンプルなものになります。
```dockerfile:firelens/Dockerfile
FROM public.ecr.aws/aws-observability/aws-for-fluent-bit:init-2.29.0
COPY extra.conf /fluent-bit/etc/extra.conf
COPY parsers_json.conf /fluent-bit/etc/parsers_json.conf
```

設定ファイルについては、parserは開発環境と同じになりますが、`fluent-bit.conf`については扱いが異なります。  
具体的には、AWS側が用意したカスタム項目を使って、`fluent-bit.conf`から設定ファイルをincludeする形で利用するため、
`fluent-bit.conf`から呼んで頂く`extra.conf`を別に定義しています。

```conf:firelens/parsers_json.conf
[PARSER]
    Name        json
    Format      json
    # Command       |  Decoder    | Field | Optional Action   |
    # ==============|=============|=======|===================|
    Decode_Field_As   json          log
```

```conf:firelens/extra.conf
[SERVICE]
    Parsers_File /fluent-bit/etc/parsers_json.conf
    Flush 1
    Grace 30

# コンテナ名 + firelens...の形式になるのでそれをMatchで引っ掛けてログをJson形式にParseする
[FILTER]
    Name parser
    Match *rails-app-firelens-*
    Key_Name log
    Parser json

# Parseされた中からnameキーにActiveRecordが入っているものにタグをつけ、それ以外のタグを削除する
# SQLの出力は非常に量が多い割に有用になることは少ないのでFirehoseでS3におくりたい
[FILTER]
    Name rewrite_tag
    Match *rails-app-firelens-*
    Rule $name ^(ActiveRecord)$ active_record false

# Parseされた中からlabelキーが存在するものに、labelの値のタグをつける
# labelのついたものは解析用に利用できるものがあると考える
[FILTER]
    Name rewrite_tag
    Match *rails-app-firelens-*
    Rule $payload['label'] .+ logdata.$payload['label'] true

[OUTPUT]
    Name kinesis_firehose
    Match *active_record
    region ap-northeast-1
    delivery_stream put-s3-sample-metrics-logs

[OUTPUT]
    Name cloudwatch_logs
    Match *rails-app-firelens-*
    region ap-northeast-1
    log_group_name /sample-metrics-fluentbit
    log_stream_prefix fluentbit-
    auto_create_group true
    log_retention_days 30
```

OUTPUTプラグインがkinesisやcloudwatchになるのは当然として、一番留意が必要なのはMatchのルールになります。  
firelensを通過したログは、ecsのコンテナの設定を考慮した名前に`-firelens`の接尾字を付与してきますので、これを前提として記述する必要があります。

WebアプリケーションとFireLensのイメージがビルドできたら、ECRへpublishしましょう。

手順としては、ECRにリポジトリを作成した後、下記コマンドでpublishすることができます。  
(前提として、awsコマンドのインストール、ログイン、ログインユーザーのECRに関するIAMロールが必要です。こちらを[参考](https://docs.aws.amazon.com/ja_jp/AmazonECR/latest/userguide/docker-push-ecr-image.html)にしてください。)
```bash:dockerイメージのpublish
aws ecr get-login-password | docker login --username AWS --password-stdin https://{アカウントID}.dkr.ecr.ap-northeast-1.amazonaws.com
docker build -t firelens-fluentbit .
docker tag firelens-fluentbit {アカウントID}.dkr.ecr.ap-northeast-1.amazonaws.com/firelens-fluentbit:2.29.0
docker push {アカウントID}.dkr.ecr.ap-northeast-1.amazonaws.com/firelens-fluentbit:2.29.0
```

## publish
(今回のサンプルのためにRDSを用意したくなかったのでpostgresもECSで起動させるためにイメージを追加しています)
![ecr](/images/metrics/ecr.png)

# ECS Fargate
WebアプリケーションとFireLensのイメージをECRへアップロードできたら、次はECSを定義していきます。

## クラスター
今回はFargateで実験していくため、クラスターテンプレートは「ネットワーキングのみ」一択になります。

クラスター名は任意、VPCについては既存を使いまわしたいかどうかで判断してください。
タグ名の追加は不要です。

`CloudWatch Container Insights` はビジネスアプリケーションであれば必要ですが、カスタムメトリクスとして課金対象のメトリックが追加されるため、今回は設定しません。

## タスク定義
### IAM
今回、ECSを実行するロールは、ECSでタスク実行するポリシー(`AmazonECSTaskExecutionRolePolicy`)に加えて、場合によってCloudWatchグループの作成(`logs:CreateLogGroup`へのアクセス許可)を付与しておく必要があります。  
既にあるロググループに追加する分には不要です。

また、後でkinesis->S3の経路を作成しますが、ECSの実行ロールに対し、Kinesisへアクセスするためのポリシー(`AmazonKinesisFirehoseFullAccess`)のアタッチが必要になります。(IAMにある程度詳しければ、個別に許可してもよいです)

### railsのタスク定義
fargateのため、特にさわれるパラメータはありません
![ecs](/images/metrics/ecs1.png)
![ecs](/images/metrics/ecs2.png)

リソースは最低限でぜんぜん大丈夫です。

コンテナ名はfluent-bitの設定に影響するので注意してください。ここでは、先程ECRへpublishしたイメージを使用します。
![rails](/images/metrics/rails1.png)
fargateにおいて、隣のコンテナは127.0.0.1(localhostはだめ)のネットワーク上に存在します。  
今回はfargateでdbを起動してしまっているので、そのためのHostを設定しています。  

きちんとRDSを設定した方はそのようにしてください。
![rails](/images/metrics/rails2.png)

ログ設定で、使用するドライバーを「awsfirelens」に変更します。ログオプションは空で良いです。
![rails](/images/metrics/rails3.png)

### dbのタスク定義
(マナー違反な使い方ですが、一応タスク定義も記載します。本番で真似しないように…。)
![db](/images/metrics/db1.png)
![db](/images/metrics/db2.png)
![db](/images/metrics/db3.png)
![db](/images/metrics/db4.png)

dbは特にルーティングするつもりがないのでcloudwatchに垂れ流します。

ポイントはヘルスチェックの設定で、この状態変化にrailsのコンテナが依存している形になっています。

### log_routeのタスク定義
まず、ページ下部にある「ログルータの統合」で、Firelensの統合を有効にしましょう。
![log](/images/metrics/log1.png)
これによって、設定できるコンテナに「log_router」が追加されます。
![log](/images/metrics/log2.png)
![log](/images/metrics/log3.png)
log_router本体のログはCloudWatchに流しましょう。設定ファイルの誤りや権限不足のログを閲覧することができます。

### 仕上げ
最後に、jsonでしか変更できない項目を追加します。
![log](/images/metrics/log4.png)

をクリックし、タスク定義のjsonを開きます。
`log_router`の設定にある`firelensConfiguration`を下記のように書き換えます。
もし、項目がない場合は追加してください

```json:ecs
...
            "image": "${アカウントID}.dkr.ecr.ap-northeast-1.amazonaws.com/firelens-fluentbit:2.29.0-10",
            "startTimeout": null,
            "firelensConfiguration": {
                "type": "fluentbit",
                "options": {
                    "config-file-type": "file",
                    "config-file-value": "/fluent-bit/etc/extra.conf"
                }
            },
            "dependsOn": null,
...
```
この設定によってextra.confをfluentbitの設定からincludeしてくれるようになります。

ここまで完成したらタスク定義を保存しましょう。

## S3/Kinesisの準備
今回設定したFluentBitはActiveRecordのログをS3にぶん投げるので、対応するKinesisとS3の設定が必要です。

(これによってCloudwatchの課金を避けられます。代わりにKinesisやS3の料金が発生しますがこちらのほうが安いです)

### S3
S3はデフォルトの設定のまま作成してください。KinesisはS3へのアクセス許可を付与するので、特に公開設定も不要です。
![s3](/images/metrics/s3.png)

### kinesis
kinesisは配信ストリームを管理するプラットフォームです。今回は、ログストリームをKinesisに送信し、gzip圧縮したストリームをS3に保存します。
また、S3には一日一つのファイルを作成するように、フォーマットを指定します。
![kinesis](/images/metrics/kinesis1.png)
配信ストリームは任意です。送信先のS3には先程作成したバケットを指定してください。
![kinesis](/images/metrics/kinesis2.png)
![kinesis](/images/metrics/kinesis3.png)
![kinesis](/images/metrics/kinesis4.png)

S3バケットプレフィックスは下記のように指定します
```
year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}

エラー出力はこちら
year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}
```
year,monthなどを指定している点がS3におけるパーティションの指定になります。
Athenaで検索する際などにスキャン範囲を限定させる際に役に立ちます。(今回の検証では意識しませんが)

kinesisを作成し終わったら、ECSのタスク実行ロールに「`AmazonKinesisFirehoseFullAccess`」を付与しておきましょう。  
よりよい方法は、[作成したkinesisのみにアクセスできるように指定](https://docs.aws.amazon.com/ja_jp/firehose/latest/dev/controlling-access.html#access-to-firehose)する方法です。

## ECSサービスの起動
作成したタスク定義を使って、ECSサービスを起動します。

ECSサービスは設定された内容に従ってFargateを起動するようにします。
![ecs](/images/metrics/ecs3.png)
今回、アプリケーションは確認できれば良いのでタスクの数は1とし、他の項目についてもデフォルトで問題ありません。

ロードバランサは高いため、検証の場合は必要ありません。Railsをポート3000で起動しているため、public ipへのアクセス時にポート番号指定が必要になる点に留意してください。

サービスの設定が完了したら、タスク欄でFargateを起動するタスクが追加されるのを待ちます。
![ecs](/images/metrics/task1.png)
起動成功した場合はRUNNINGと表示されます。

タスクページではパブリックIPや、コンテナログの確認が可能です。  
firelensでルーティングされたログについては、このUIからでは確認できません。
![ecs](/images/metrics/ecs4.png)
![ecs](/images/metrics/ecs5.png)

うまく行っているようであれば、public ipへのcurlで動作確認することが可能です。

```bash
curl "http://35.78.217.14:3000/users/1?query=konitiwa"

{"id":1,"name":"hoge","created_at":"2023-01-03T15:45:47.170Z","updated_at":"2023-01-03T15:45:47.170Z"}
```

# CloudWatchの確認
FluentBitの設定として追加した`extra.conf`のOUTPUTプラグインには下記のように指定しました。
```conf
[OUTPUT]
    Name cloudwatch_logs
    Match *rails-app-firelens-*
    region ap-northeast-1
    log_group_name /sample-metrics-fluentbit
    log_stream_prefix fluentbit-
    auto_create_group true
    log_retention_days 30
```
log_group_nameと同名のログがCloudWatchに作成されていれば、その中にログストリームが保存されているはずです。
ストリームの命名規則は、「`${log_stream_prefix}${tag}`」の形式を取るため、「`fluentbit-rails-app-firelens-UUID`」になります。

![cw](/images/metrics/cw1.png)
![cw](/images/metrics/cw2.png)
![cw](/images/metrics/cw3.png)

ログを確認すると、先程curlしたログが記録されています。

## S3の確認
少し時間がかかりますが、S3にもログが転送されます(ActiveRecordのSQLログ)
![s3](/images/metrics/s3-2.png)

なお、S3に保存されているファイルはkinesisによりgzip圧縮されるように設定していますが、UIからダウンロードした際には展開された状態で落ちてきます。  
**しかしファイル名の拡張子は`gz`のままなので注意してください。**

# 参考
- [awslogs ログドライバーを使用する](https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/using_awslogs.html)