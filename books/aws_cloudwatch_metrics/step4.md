---
title: "docker-composeで体験するFluentBit"
free: true
---
# FluentBit
ログルーティングを実装するに当たり、一番厄介に思う人が多いと思われるものがFluentBitです。  
なぜなら、ログルーティングは考慮せずとも一定のアプリケーションを運用する分には言うほど困らず、ビジネスがスケールするにつれて足を引っ張ってくるものであり、場合によっては「ログルーティング」なんて言葉に出会わずにここまで育ってきた人もいることでしょう。

アプリケーションの開発やプログラミング言語の習得は、経験するにつれてイニシャルコストが低減されていきますが、そういった汎用的な経験がFluentBitにはあまり通用しません。  
そのため、ログルーティングと向き合った場合の学習コストは比較的大きく見えがちで、億劫に思われることと思います。

本稿においては、FluentBitをかんたんに体験いただくためにdocker-composeを使用して、その結果を眺めてみることとします。
ログを吐き出すアプリケーションコードは何でも良いのですが、サンプルを動かしたい場合はgithubよりサンプルコードをダウンロードして動かしてみてください。

https://github.com/ange-k/metrics-sample

## docker-compose
今回利用するdocker-composeは下記のとおりです。

構成として、ログ出力を行うためのサンプルアプリケーションとしてRailsを起動します。
依存として、nginx, postgresを起動し、アプリケーションログをfluent-bitに転送する構成を取ります。

```yml:docker-compose.yaml
services:
  db:
    image: postgres:15.1
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: 'admin'
      POSTGRES_PASSWORD: 'password'
  web:
    build: .
    logging:
      driver: fluentd
      options:
        fluentd-address: "localhost:24224"
        fluentd-async-connect: "false"
        tag: "rails_dev"
    volumes:
      - .:/usr/src/app
    ports:
      - "3000:3000"
    depends_on:
      - db
      - fluent-bit
  nginx:
    build:
      context: .
      dockerfile: ./nginx/Dockerfile
    logging:
      driver: fluentd
      options:
        fluentd-address: "localhost:24224"
        fluentd-async-connect: "false"
        tag: "nginx"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf
      - public:/app/public
      - tmp:/app/tmp
    ports:
      - "80:80"
    depends_on:
      - web
      - fluent-bit
  fluent-bit:
    image: fluent/fluent-bit
    volumes:
      - ./fluent-bit.conf:/fluent-bit/etc/fluent-bit.conf
      - ./parsers.conf:/fluent-bit/etc/parsers.conf
      - ./log:/log:rw
    ports:
      - "24224:24224"
volumes:
  public:
  tmp:
```

ポイントは2点です。
- logging.driverとしてfluentdを指定。オプションでコンテナとして起動するfluent-bitを指定している
- fluent-bitはコンフィグファイルをvolumesで共有している

railsが使用するDockerfileは下記です。

```dockerfile:Dockerfile
FROM ruby:3.1.3-bullseye AS build
COPY Gemfile Gemfile.lock ./
RUN gem install bundler:2.3.26
RUN bundle install

FROM ruby:3.1.3-slim-bullseye AS base
# https://rubygems.org/gems/bundler/versions/1.17.2?locale=ja
RUN gem install bundler:2.3.26
WORKDIR /usr/src/app

FROM base AS deploy
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build Gemfile* ./
COPY . .
COPY entrypoint.sh /usr/bin/
RUN apt update -qq && apt-get install -y lsb-release gnupg wget
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - && \
    sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
RUN apt update -qq && \
    apt-get install -y \
        postgresql-client
RUN bundle install
RUN \
    apt-get clean autoclean && \
    apt-get autoremove --yes && \
    rm -rf /var/lib/{apt,dpkg,cache,log}/
ENTRYPOINT ["entrypoint.sh"]
EXPOSE 3000
ENV RAILS_ENV development
ENV RAILS_LOG_TO_STDOUT true
CMD ["rails", "server", "-b", "0.0.0.0"]
```

ガチャガチャ書いていますが、重要なのは下記2行です。(ほかはRailsを起動するイメージをなるべく小さくできないかな〜とか脱線した結果です。そんなうまくいきませんでした)
```
ENV RAILS_ENV development
ENV RAILS_LOG_TO_STDOUT true
```
今回はprodなんてものはないので、dev環境をイメージで指定しています。
また、標準出力にログを吐き出すようにフラグを立てています。(前章でconfigに書いたif分岐です)

## fluent-bitのコンフィグファイル
FluentBitのメインとなる設定ファイルは下記のとおりです。
設定の解説をコメントしています。

```conf:parsers.conf
# https://docs.fluentbit.io/manual/pipeline/parsers/configuring-parser
# https://docs.fluentbit.io/manual/pipeline/parsers/decoders
[PARSER]
    Name        json # parserの名前です。任意です。
    Format      json # パースするログの形式です
    # Command       |  Decoder    | Field | Optional Action   |
    # ==============|=============|=======|===================|
    Decode_Field_As   json          log
```
Decode_Field_Asは、ログに含まれているlogフィールドをjsonとしてデコードし、フィールドとして解釈できるようにしています。  
*(もしParserを置かない場合はエスケープされたjsonログが送られてきているので、CloudWatch等で解釈することができません)*  
この際、container_idやらsourceなど、不要なフィールドを削ぎ落とし、出力されたlogフィールドだけに置き換える役割も担っています。

```conf:fluent-bit.conf
# https://docs.fluentbit.io/manual/v/1.3/service
# FluentBitの振る舞いを定義しています。
[SERVICE]
    Flush        5      # inputされたログをためて吐き出す(flush)までの時間
    Daemon       Off    # プロセスをデーモンとして起動するかどうか。コンテナ実行の場合はOffです。
    Log_Level    info   # fluentbitそのもののログレベルを指定します

    Parsers_File /fluent-bit/etc/parsers.conf # 前述したParserを定義したファイルへのパスです

    HTTP_Server  Off     # https://docs.fluentbit.io/manual/administration/monitoring のための組み込みサーバを起動するか
    HTTP_Listen  0.0.0.0
    HTTP_Port    2020

# https://docs.fluentbit.io/manual/pipeline/inputs
# inputプラグインの指定。ログをどうもらってくるか.
# forwardはfluentdからデータをもらうプラグイン
[INPUT]
    Name forward # https://docs.fluentbit.io/manual/pipeline/inputs/forward
    Host 0.0.0.0
    Port 24224

# https://docs.fluentbit.io/manual/pipeline/filters
# parserプラグインは、規定したParserを呼び出すことでログを解析することができます
# ここでは、jsonという名前のparserを呼び出し、logというjsonフィールドをパースすることを指示しています
# Matchにはアスタリスクが指定されているので、送られたログ全てにこのフィルタを実行します。
[FILTER]
    Name parser
    Match *
    Key_Name log
    Parser json

# https://docs.fluentbit.io/manual/pipeline/filters/rewrite-tag
# rewrite_tagプラグインは、Matchに適合した対象に対してタグをつけ直す操作を行います。
# 「$KEY  REGEX  NEW_TAG  KEEP」の形式でRuleを指定します。
# ここでは、$nameフィールドがActiveRecordならば、タグを「active_record」に書き換え、書き換え前のログを削除する、ことを指示します。
[FILTER]
    Name rewrite_tag
    Match rails_dev # docker-composeでfluentdに対して指定したtag名を指定しています
    Rule $name ^(ActiveRecord)$ active_record false

# 前の行と同じですが、Ruleが異なります
# $payload.labelフィールドを参照し、値が存在していれば(.+なので)、「logdata.値」にタグを書き換えることを指示しています。
# このように、Ruleの中でjsonフィールドを参照し、フィールドの値を引っ張ってきてタグ付けすることができます
[FILTER]
    Name rewrite_tag
    Match rails_dev
    Rule $payload['label'] .+ logdata.$payload['label'] false

# https://docs.fluentbit.io/manual/pipeline/outputs
# fileプラグインはMatchに適合したログの出力先を規定します。
# 特に指示しない場合、ファイル名はタグから自動生成されます。
[OUTPUT]
    Name file
    Match active_record
    Path /log/
    File sql

[OUTPUT]
    Name file
    Match logdata.*
    Path /log/
    File logdata

[OUTPUT]
    Name file
    Match rails_dev
    Path /log/

[OUTPUT]
    Name file
    Match nginx
    Path /log/
```

## 出力される内容
今回はログ出力をみたいのみですので、適当にAPIを実装して、前章で書いたLogFormatでログ出力してみましょう。
実装が面倒であれば、githubのサンプルコードを利用してください。

## example1
なんの意味もないログを出力するコードを書きます
```ruby:basicロガーサンプル
logger.info(LogFormatter.basic("aiueo"))
```

上記を書いたエンドポイントを実行します
```bash:curlの実行
curl  http://localhost:3000/users

[{"id":1,"name":"hoge","created_at":"2023-01-05T11:12:32.075Z","updated_at":"2023-01-05T11:12:32.075Z"},{"id":2,"name":"fuga","created_at":"2023-01-05T11:12:32.078Z","updated_at":"2023-01-05T11:12:32.078Z"}]
```

下記2つのログファイルが作成されます。

```log:log/rails_dev
rails_dev: [1672917203.000000000, {"host":"96e9f7d0b7ef","application":"Semantic Logger","environment":"development","timestamp":"2023-01-05T11:13:23.153936Z","level":"debug","level_index":1,"pid":1,"thread":"puma srv tp 001","named_tags":{"request_id":"ca2c882c-fc2a-470e-af94-f64547c17c3b","ip":"172.22.0.1"},"name":"Rack","message":"Started","payload":{"method":"GET","path":"/users","ip":"172.22.0.1"}}]
rails_dev: [1672917203.000000000, {"host":"96e9f7d0b7ef","application":"Semantic Logger","environment":"development","timestamp":"2023-01-05T11:13:23.256114Z","level":"debug","level_index":1,"pid":1,"thread":"puma srv tp 001","named_tags":{"request_id":"ca2c882c-fc2a-470e-af94-f64547c17c3b","ip":"172.22.0.1"},"name":"UsersController","message":"Processing #index"}]
rails_dev: [1672917203.000000000, {"host":"96e9f7d0b7ef","application":"Semantic Logger","environment":"development","timestamp":"2023-01-05T11:13:23.274210Z","level":"info","level_index":2,"pid":1,"thread":"puma srv tp 001","named_tags":{"request_id":"ca2c882c-fc2a-470e-af94-f64547c17c3b","ip":"172.22.0.1"},"name":"UsersController","payload":{"type":"message","content":"aiueo"}}]
rails_dev: [1672917203.000000000, {"host":"96e9f7d0b7ef","application":"Semantic Logger","environment":"development","timestamp":"2023-01-05T11:13:23.310613Z","level":"info","level_index":2,"pid":1,"thread":"puma srv tp 001","duration_ms":54.36764597892761,"duration":"54.4ms","named_tags":{"request_id":"ca2c882c-fc2a-470e-af94-f64547c17c3b","ip":"172.22.0.1"},"name":"UsersController","message":"Completed #index","payload":{"controller":"UsersController","action":"index","format":"*/*","method":"GET","path":"/users","status":200,"view_runtime":24.0,"db_runtime":3.76,"allocations":7268,"status_message":"OK"}}]
```
付加されている情報が多く見難いですが、プレーンな本来のログの内容は「payload」フィールドの中に入っています。  
basicメソッドで出力したログは3行目にあります。

```log:log/sql
active_record: [1672917203.000000000, {"host":"96e9f7d0b7ef","application":"Semantic Logger","environment":"development","timestamp":"2023-01-05T11:13:23.227232Z","level":"debug","level_index":1,"pid":1,"thread":"puma srv tp 001","duration_ms":1.027251958847046,"duration":"1.027ms","named_tags":{"request_id":"ca2c882c-fc2a-470e-af94-f64547c17c3b","ip":"172.22.0.1"},"name":"ActiveRecord","message":"ActiveRecord::SchemaMigration Pluck","payload":{"sql":"SELECT \"schema_migrations\".\"version\" FROM \"schema_migrations\" ORDER BY \"schema_migrations\".\"version\" ASC","allocations":11,"cached":null}}]
active_record: [1672917203.000000000, {"host":"96e9f7d0b7ef","application":"Semantic Logger","environment":"development","timestamp":"2023-01-05T11:13:23.283588Z","level":"debug","level_index":1,"pid":1,"thread":"puma srv tp 001","duration_ms":0.5650298595428467,"duration":"0.565ms","named_tags":{"request_id":"ca2c882c-fc2a-470e-af94-f64547c17c3b","ip":"172.22.0.1"},"name":"ActiveRecord","message":"User Load","payload":{"sql":"SELECT \"users\".* FROM \"users\"","allocations":21,"cached":null}}]
```
こちらはactive recordの実行ログです。
SematicLoggerにより、nameフィールドに`ActiveRecord`が挿入されるため、このようにActiveRecordの実行ログをアプリケーションログから分離することができます。

Ruleに書いた、「`$name`」が正規表現「`^(ActiveRecord)$`」を満たすとき、という条件をlog/sqlに書き出されたログは満たしていることがわかると思います。
```conf:fluent-bit.confの一部
[FILTER]
    Name rewrite_tag
    Match rails_dev
    Rule $name ^(ActiveRecord)$ active_record false
```

## example2
では、少し複雑なロギングも試してみましょう。

下記のようなログ出力をしてみます。
```ruby:example
    logger.info(LogFormatter.athena({
        "user_id": @user.id,
        "data": params[:query]
      },
        "user_show"
    ))
```
このログは、ユーザの実行したクエリパラメータをそのままdataフィールドとして記録します。

早速実行してみましょう。
```bash:example
curl "http://localhost:3000/users/1?query=hoge"

{"id":1,"name":"hoge","created_at":"2023-01-05T11:12:32.075Z","updated_at":"2023-01-05T11:12:32.075Z"}⏎
```

3つのログファイルが作成されますが、そのうち2つはexample1とほぼ同じのため、今回作成されたファイルだけを示します。

```log:log/logdata
logdata.user_show: [1672918013.000000000, {"host":"96e9f7d0b7ef","application":"Semantic Logger","environment":"development","timestamp":"2023-01-05T11:26:53.870489Z","level":"info","level_index":2,"pid":1,"thread":"puma srv tp 003","named_tags":{"request_id":"80d8abdc-94fa-4c1c-9d9d-c5ee5870a03e","ip":"172.22.0.1"},"name":"UsersController","payload":{"label":"user_show","user_id":1,"data":"hoge"}}]
```
payloadフィールドにcurl実行時につけたデータが含まれていることがわかります。

## おわりに
なんとなくfluent bitのイメージができたでしょうか。

AWSではoutputプラグインとして、ファイル書き込みではなくCloudWatchやKinesisを指定することになりますが、fluent bitの基本は変わりません。

inputにログを流して、正規表現を駆使してタグ付けして、そのタグをうまく使って意図した相手にログを渡せばよいのです。

もしかすると、全ログが1行で出てくるのに拒否感を覚えるかもしれません。
しかし、これからのログは人間が読むだけでなく機会にも読ませなければならないことを忘れないでください。  
複数行に渡ったログを適切に解釈することはとても難しいことです。

じゃあ人間は諦めろと言っているわけではないです。適切なツールを使ったらちゃんと読めるようになりますので心配しないでください。  
もちろん、grepのように単純に行くわけではないですが、grepとちがってスケールしてもなんの考慮もなく読むことができます。  
だれしも数十、数百台のサーバに散らばったログをscpでとってきて結合してgrepなんかしたくないはずです。
