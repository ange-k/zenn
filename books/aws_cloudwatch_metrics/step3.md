---
title: "CloudWatchを活用できるログ設計"
free: true
---
# 監視サービスの構成要素
[書籍「入門監視」](https://amzn.to/3Vfba47)によると、監視サービスは5つのコンポーネントにより構成されます。

- データ収集
  - ログ、メトリクスデータ収集を担う。
- データストレージ
  - データの保存先。メトリクスの場合は時系列データとして記録されるべき。
- 可視化
  - データや監視状況を目に見える形で表示してくれるツール
- 分析とレポート
  - サービスのSLA(Service Level Agreement)のための分析や利用者動向の調査などを実現するツール。
- アラート
  - 問題が起きたときに通知してくれるもの
  - だけど、書籍「入門監視」では著者友人の言葉を引用する形で下記のように記載される。
    - 「監視は、質問を投げかけるためにある」
      - アラートは結果の一つの形でしかなく、収集しているメトリクスやグラフが1対1で対応している必要はない
    - 私自身の解釈ですが、日々メトリクスを眺めていると、ちょっとした違和感を拾うことがあります。今日はいつもよりアクセス数が少ないとか、意図しないHTTPステータスを返した様子があるとか、CPU使用率が上がってきていることとか、メモリ使用率がじわじわ悪化していることとか。  
    そのどれもが瞬時にアラートとなるものではありませんが、間違いなく「これは正常なのか？」といつ疑問を開発者にもたらすには十分なものです。

これらの構成要素をCloudWatchは内包しているため、うまく活用することできちんと監視・運用していくことができます。

# AWSにおけるCloudwatchへのデータ連携について
今回、アプリケーションを動作させるためにECS Fargateを利用します。Fargateを使った場合のログ連携方法はいくつかありますが、今回はログルーティングを受け持ってくれる[FireLens](https://dev.classmethod.jp/articles/ecs-firelens/)を利用します。

[The Twelve-Factor App](https://12factor.net/ja/)をご存知でしょうか？  
Webアプリケーションとしてあるべき姿のひとつとして、[ログをイベントストリームとして扱う](https://12factor.net/ja/logs)ことが明記されています。  
要は、アプリケーションがログの出力先をどうするとかそんなことは考えさせるなということです。

FargateとFireLensを使うことにより、ログの出力先の設定はサイドカーとして動作するFireLens(FluentBit)に押し付ける事ができるので、アプリケーションは純粋にログ設計に取り組めば良くなります。これでいつAWSをやめるとなっても、ログ出力に関してアプリケーションを改修する必要はないはずです。  
(アプリケーションのログ出力はFluentBitがハンドリングしてくれているので、出力先を変更するだけの話になる。FluentBitをやめることはできないがこれはOSSなのでベンダーロックインはされない)

## FireLensでできること
FireLensはFluentBitを利用するので、FluentBitにできることはすべてできます。  
具体例として、Classmethodさんの記事を紹介致します。

- [特定条件に当てはまるログを削除](https://dev.classmethod.jp/articles/filtering-healthchecklog-with-fluent-bit/)
- [すべてのログをS3へ、エラーをCloudWatchへ](https://dev.classmethod.jp/articles/storing-error-logs-and-all-logs-separately-in-firelens/)
- [特定json keyだけCloudWatchに連携する](https://dev.classmethod.jp/articles/firelens-cloudwatchlogs-specific-json-key/)

## 満たしたい要件
今回取り組むRailsアプリケーションでは、下記の要件を満たす構成にしたいと思います。
1. metricsに関わる出力、エラーに関わる出力、解析に必要なログだけをCloudWatchに連携する
1. CloudWatchで必要なログを検索できるようにする
1. 上記以外のログはS3に保存する
1. エラーログについてはエラーレベルとエラーコードを紐付ける

## ログ設計の指針
大枠の要件が決まったので、ログの設計を考えましょう。  
古来のログは、何も考えずにメッセージを投げ込むのみが役割でした。

`logger.info('yobareta method name')`とか、`logger.error(e)`とかです。

そして、エラーが起きると(=エラーレベルのイベントが発生すると)、ログファイルを眺めてエラーを特定し、何が起きたのかを推理して運用します。  
しかしながら、この運用が通用するのはそのチームがそのアプリケーションをよくよく理解しているときだけにとどまります。

そうでなければ、例外名から原因を導き、なぜそんな事が起きたのかデータフローを洗い直すことになるでしょう。  
こんなことをやっていてはいつまでたっても「組織の流動化」とか「運用の委託化」とか「運用コストの削減」とかいう話は進みません。

より価値あるログは、適切に可視化することで気づきを与えてくれるものであるべきです。  
ユーザのある振る舞いを観測する目的で書かれたinfoログを統計することでなにか価値が生まれるかもしれません。  
発生するエラーの頻度から周期性を見出すことができるかもしれません。  
送信されたデータの一部をログに落とし、それを統計・解析する需要が眠っているかもしれません。

ログを可視化するためには、システマティックにログを振り分けるための目印が何かしら必要になります。ログレベルはそのうちの一つの概念に過ぎません。  
おなじinfoログを出すにしても、「商品を検索したワード」と「購入履歴を検索したワード」は見分けられるようにロギングして然るべきです。  
おなじerrorログを出すにしても、「10分の間に5回であれば異常」なものもあれば、「1回でも発生したら異常」なものもあるでしょう。

ログのフォーマットに気を使うことで、表現力豊かなロギングが可能になり、運用ドキュメントに明示的な記述を増やすことが可能になります。

# jsonログフォーマットでロギングする
では、サンプルとしてやっつけロギングで運用されがちなRailsをサンプルとして解説を進めます。  
javaでも、phpでもJson形式のログフォーマットに対応するようなロギングライブラリはありますので、適宜読み替えてください。

今回利用するのは、[Rails Semantic Logger](https://github.com/reidmorrison/rails_semantic_logger)です。

本ロガーを用いることで、設定を追加することなく下記が達成されます。

- ログ出力がjson等に変更可能になる。
  - jsonに変更することによってfluentbitでのログルーティングやCloudWatch Insightsの検索を最大限活用できるようになる。
- コンテキスト情報(クラス名、IPアドレス、プロセスID…)が追加される

## 導入
[公式](https://logger.rocketjob.io/rails.html)の手順に従ってかんたんに導入することができます。

最低限のGemfileは下記のようになります。

```ruby:Gemfile.rb
source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby "3.1.3"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 7.0.4"

# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"

# Use the Puma web server [https://github.com/puma/puma]
gem "puma", "~> 5.0"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mingw mswin x64_mingw jruby ]

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# https://logger.rocketjob.io/rails.html
gem "amazing_print"
gem "rails_semantic_logger"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mingw x64_mingw ]
end

group :development do
  # Speed up commands on slow machines / big apps [https://github.com/rails/spring]
  # gem "spring"
end
```

loggerそのものはインストール段階で有効になります。
今回は開発環境からdocker-composeを使いつつFluentBitの挙動をみつつAWSを構築したいので、開発環境でもログ出力先を標準出力へと向けられる設定を追加しておきます。

```ruby:config/environments/development.rb
  # logger
  config.rails_semantic_logger.format = :json
  # デフォルトの名前付きタグ。
  config.log_tags = {
    request_id: :request_id,
    ip:         :remote_ip,
  }
  if ENV["RAILS_LOG_TO_STDOUT"].present?
    $stdout.sync = true
    config.rails_semantic_logger.add_file_appender = false
    config.semantic_logger.add_appender(io: $stdout, formatter: :json) # 標準出力へ
  end
```

## 統一したログを出力する
jsonでログを出すだけならこれだけで十分ですが、運用するには不十分です。

jsonでログを出しても、ログルーティングするための目印がログレベルやコントローラ名くらいしかありません。  
そこで、ログ出力のためのテンプレートを決めてしまいます。

```ruby:config/initializers/log_formatter.rb
# frozen_string_literal: true

class LogFormatter
  class << self
    def basic(content, type='message')
      {
        type: type,
        content: content
      }
    end

    def athena(data_map, data_label)
      {
        label: data_label
      }.merge(data_map)
    end

    def exception(exception, code='RUNTIME_EXCEPTION')
      {
        exception: exception,
        code: code
      }
    end
  end

end
```
例として、下記3つを定義しました。
ここで定義するルールが、アプリケーションが発するメトリクスの表現力を決めてしまうので、本番で採用する際には必要最低限かつ表現したいメトリクスを表現できるように設計しましょう。

- basic
  - 単純なメッセージログを出力するためのフォーマット。contentに入れた内容を表示する。
  - typeに別の定型文をいれて、それだけを検索するような用途も可能。
    - バッチ処理だけ別のラベリングにするとか。(バッチを分けろよという話は置いといて)
- athena
  - athenaを使った分析など、検索だけではなく統計・解析もしたいデータをロギングするためのフォーマット。
    - ラベル付けしつつ、任意のjsonデータをそのままロギングすることが可能。
- exception
  - 例外時用のフォーマット。
  - 例外コードはどっかにenumで持ったほうが良さそう。なるべくRUNTIME_EXCEPTIONにならないようにエラーコードを付与してあげる。
  - エラーコードの設計 = 運用設計に同じ。
    - アラートルール上、分別したいかどうかを基準におきつつ、具体的なエラーコードになるようにする。
    - エラーコード基準に運用ドキュメントを整備すること。特に特定の手運用が必要なエラーは専用のエラーコードにしたほうが良い。

あとはこれを使ってログを出力するようなコーディング規約で頑張れば、解析可能なログデータを手に入れることができます。
```ruby: example
    logger.info(LogFormatter.athena({
        "user_id": @user.id,
        "data": params[:query]
      },
        "user_show"
    ))
```
もちろん、`basic`を定義せず、そのまま`logger.info('hogehoge')`してもよいでしょう。  
ただ、なにか意味のあるinfoログになっているかは考えたほうが良いです。

次の章では、このログフォーマットを使ってFluentBitの挙動をローカルで確認してみましょう。
