---
title: "CloudWatch メトリクスとアラート"
free: true
---

# 独自のメトリクスを追加する
ログの話をしたので、次はメトリクスについて記載します。

前章には、下記のようなログをCloudWatch Insightsを使って統計するシーンが有りました。

```
stats pct(duration_ms, 99) by message
| filter ispresent(duration_ms)
```

![cwi](/images/metrics/cwi5.png)

もちろん、これだけでも性能指標を定期的に確認することで異常に気づくきっかけにできるでしょう。  
しかしながら、それでは人間の手が介在してしまい、面倒くさいことこの上ありません。

そこで、ログからエンドポイントごとの99%ileを取り出し、メトリクスとしてCloudWatchで扱えるようにしてみましょう。  
メトリクスとして登録すれば、ダッシュボードからいつでも99%ileの性能指標を時系列グラフとして確認することができるようになります。

性能の劣化を検知した場合、スケールアウトやスケールアップを判断するきっかけを与えてくれるでしょう。

では、ひとまずメトリクスとして拾う対象のログについて、ある程度の数がほしいのでcurlを定期実行してログを追加します。
LinuxやMacでかんたんに定期実行するにはwatchコマンドがおすすめです。(yumやらbrew installが必要な場合もあります)
```bash
watch -n8 curl "http://35.78.185.17:3000/users" # 8秒間隔でcurlを叩いている
```

## メトリクスフィルター
AWSにおいて、Cloudwatch logからメトリクスを作成するには「[メトリクスフィルター](https://docs.aws.amazon.com/ja_jp/AmazonCloudWatch/latest/logs/MonitoringPolicyExamples.html)」を使用します。

メトリクスフィルターに使用可能な構文は[こちら](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/FilterAndPatternSyntax.html)で解説されています。  
今回はJSONのログを解析するので、対応した項を読んでみてください。  

CloudWatchのアプリケーションログを蓄積しているロググループから、「メトリクスフィルター」を作成してみましょう。
![metrics](/images/metrics/metric1.png)

下記のような画面が表示されます。実際に蓄積しているログデータを選択し、フィルターの設定が正しいか確認することができます。
![metrics](/images/metrics/metric2.png)

### フィルタの設定

今回メトリクスとして登録したい対象のログは下記のような構造を持つログです。
`payload.controller`および`payload.action`でエンドポイントが概ね確定します。

値としては`duration_ms`を取得します。
```json
{
  "host": "ip-172-31-7-221.ap-northeast-1.compute.internal",
  "application": "Semantic Logger",
  "environment": "development",
  "timestamp": "2023-01-07T04:47:57.883280Z",
  "level": "info",
  "level_index": 2,
  "pid": 1,
  "thread": "puma srv tp 001",
  "duration_ms": 1.822982999961823,
  "duration": "1.823ms",
  "named_tags": {
    "request_id": "a35e8b76-de9e-4f7c-a3ad-95b3c455dd36",
    "ip": "152.117.212.132"
  },
  "name": "UsersController",
  "message": "Completed #index",
  "payload": {
    "controller": "UsersController",
    "action": "index",
    "format": "*/*",
    "method": "GET",
    "path": "/users",
    "status": 200,
    "view_runtime": 1.17,
    "db_runtime": 0.44,
    "allocations": 679,
    "status_message": "OK"
  }
}
```

これらを抽出するためにはメトリクスフィルターの構文に従って値を指定する必要があります。  

ドキュメント記載の通り、JSON形式のログに対して、文字列を対象として検索するメトリクス構文は下記に従って指定します。
`{ PropertySelector EqualityOperator String }`
- PropertySelector
  - JSONのフィールドを指定するセレクタです。`$.payload.controller`のように指定します
- Equality operator
  - 等価演算子を指定します。`=`, `!=`を使用できます
- String
  - 検索対象の文字列を指定します。ワイルドカード(`*`)を指定できます

今回はエンドポイントのレスポンスタイムを取得したいので、`*Controller`を引っ掛けられたら良さそうです。試してみましょう。

![metrics](/images/metrics/metric3.png)
![metrics](/images/metrics/metric4.png)
![metrics](/images/metrics/metric5.png)
![metrics](/images/metrics/metric6.png)

フィルターパターンを入力し、「パターンをテスト」を実行します。テスト結果で、duration_msを含むログを取得できていれば成功です。そのままメトリクスフィルターを作成してみましょう。

# メトリクスを表示する
作成したメトリクスは、カスタムメトリクスとして表示可能になっています。  
「すべてのメトリクス」から、追加したメトリクスをグラフに表示してみましょう。
![metrics](/images/metrics/metric7.png)
![metrics](/images/metrics/metric8.png)
![metrics](/images/metrics/metric9.png)
![metrics](/images/metrics/metric10.png)

デフォルトでは統計を「平均」として表示しています。

「期間」1分で「平均」の場合は、その1分間に蓄積したメトリクスを統計し、その平均を表示しています。  
つまりは１分ごとの平均値が表示されています。

メトリクスの性質によって、採用すべき「[統計](https://docs.aws.amazon.com/ja_jp/AmazonCloudWatch/latest/monitoring/Statistics-definitions.html)」は異なります。今回の場合はパーセンタイルが適切でしょう。

![metrics](/images/metrics/metric11.png)

一通り試したら、「グラフをクリア」しておきましょう。

## ダッシュボード
なにかあるたびにいちいちメトリクスをグラフに追加して眺めるのは面倒くさいですね。

なので、管理したいアプリケーションごとにダッシュボードを作成することをおすすめします。  
ECSコンテナのパフォーマンスメトリクス（CPUやメモリなど）も一つのダッシュボードで表示することで、アプリケーションの状態をよりよく可視化することができます。

早速ダッシュボードを作成しましょう。
![metrics](/images/metrics/metric12.png)

今回は線グラフのコンポーネントを選びます。
![metrics](/images/metrics/metric13.png)

また、メトリクス選択の画面になるので、今回追加したカスタムメトリクスを選択していきましょう。

統計は「p99」とし、期間は５分に設定しておきます。(期間は小さいほど有意なデータになりますが、比例してお金もかかっていきます…)
![metrics](/images/metrics/metric15.png)
![metrics](/images/metrics/metric14.png)

以上の設定で、いつでもアプリケーションのカスタムメトリクスを参照できるようになりました。

# アラート
ダッシュボードは「気づき」を与えてくれるという役割では大いに活躍しますが、実際に問題が発生したときにすぐに気づくことはできません。ダッシュボードそのものには通知機能はないからです。

あるメトリクスの状況が悪化した際にシステムから通知をもらう（アラートを上げる）には`アラーム`を設定します。

![alert](/images/metrics/alert1.png)

監視する対象のメトリクスを選択します。indexを選択しておきます。
![alert](/images/metrics/alert2.png)

アラートを発生させる条件を指定していきます。統計はp99とし、条件は「`静的`」/「`以上`」を指定します。  
今回は動作を見たいので、どうみてもアラートが発生するであろう位置にしきい値を指定します。

本来は適切な値を探る必要がありますのでご注意ください。

![alert](/images/metrics/alert3.png)
![alert](/images/metrics/alert4.png)

アクションの設定では、アラートの通知先を設定することができます。既にSMSトピックがある方はそれを利用しても良いです。  
新規作成する場合は、「新しいトピックの作成」を選択し、必要な項目を入力した上で「トピックの作成」を選択してください。
![alert](/images/metrics/alert5.png)
アラートが発生した場合、通知以外にもアクションを取るオプションがあります。  
AutoScallingアクションをうまく使うことで、スケールアウト/スケールインをコントロールすることも可能です。
![alert](/images/metrics/alert6.png)
![alert](/images/metrics/alert7.png)

通知先の設定がなく、新規作成した場合は設定したメールアドレス宛に確認メールが届いているのでリンクを踏んでおいてください。
![alert](/images/metrics/alert8.png)

しばらく経過した後、アラート条件を満たしていればアラーム状態になっていると思います。
![alert](/images/metrics/alert9.png)

以上でカスタムメトリクスのアラーム登録が完了しました。

# システムメトリクスについて
ECSにおいては、[公式ドキュメント](https://docs.aws.amazon.com/ja_jp/AmazonECS/latest/developerguide/cloudwatch-metrics.html)で触れられている通り、デフォルトでクラスターが扱うサービスの単位でのCPU/メモリのメトリクスが提供されています。

EC2等においても同様であり、基礎的なメトリクスをAWSは無償で提供しています。

# おわりに
書籍の内容としては以上になります。

Cloudwatchに限らず、ログをうまく検索、統計したい、メトリクスをうまく使ってアラートを上げたい、自動化したいというニーズはアプリケーションが機能的に完成されてからニーズが高まっていくことが多いです。

しかしながら、システムでログをうまく扱うためには「構造化ログ」でなければ扱えず、アプリケーションログから発するアラートとうまく付き合うためには、発せられたアラートの要因が明確にわからなければなりません。

すなわち、一貫したルールのもとで運用されるログフォーマットとと、例外ハンドリングが必要であり、これらはアプリケーションコードによって実現されるものです。(AWS側の設定やログルータの設定ではなく)  
このため、「YAGNI」だの「too match」だの言っていると成長フェーズに載ってから痛い目を見ます。例外を明示的にするためのリファクタリングはアプリケーションが複雑であるほど難しいです。

プロダクトの安定運用と成長のために、どんなログを出しておけばいいか、どんなメトリクスを指標にするかを考え、設計していただければなと思います。


重ねてになりますが、「メトリクス」の「ディメンション」にはご注意ください。どんなサービスをつかうにせよ、カーディナリティを誤ったメトリクスは破産の原因になります。