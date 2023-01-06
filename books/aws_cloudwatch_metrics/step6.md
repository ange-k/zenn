---
title: "ログの検索・統計"
free: true
---
# CloudWatchの検索、統計
さて、5章の段階でRailsのアプリケーションコードから吐き出したログがCloudWatchやS3に蓄積できるようになりました。

しかし、ログは活用してナンボなので、人間が扱いやすくなければ意味がありません。  
そこで、`CloudWatch Logs Insights`を使用します。

![cwi](/images/metrics/cwi1.png)

[CloudWatch Logs Insightsのクエリ言語](https://docs.aws.amazon.com/ja_jp/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)は見慣れないかもしれませんが、仕様はシンプルであり、すぐに任意のログを抽出することができるはずです。

(CloudWatchへの蓄積され、検索されるまでに若干タイムラグがある点に留意してください。1分未満ではあると思います)

## e.g. アプリケーションログの抽出
今回、Railsが吐き出した`basic`メソッドを使ったログ出力にはすべて`type: 何とか`というフィールドが存在します。

であれば、typeフィールドが存在するメッセージを抽出することで、ほしいログが手に入るはずですね。

```
fields @timestamp, payload.type, payload.content, @message
| sort @timestamp desc
| filter ispresent(payload.type)
| limit 20
```

サンプルとしては上記のようになります。
`fields`は検索対象とするフィールドを記載します。その中で`@timestamp`はCloudWatchに保存された時間を、`@message`はそのログが持つ全てのフィールドが保存されています。

つまり、@messageを見れば全部見えるわけですが、これでは人間に優しくないので、見たいパラメータは`payload.type, payload.content`のように付与しておくのが無難です。

`sort`は文字の通り、`@timestamp`をつかってソートを行っています。

`filter`はSQLで言うところのwhere句に相当します。ここでは、`payload.type`に値があるものだけに絞り込んでいます。
`ispresent`以外にも様々な関数が用意されていますのでチラ見しておくといいかもしれません。   
[ドキュメント](https://docs.aws.amazon.com/ja_jp/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)の「サポートされているオペレーションと関数」に目を通してみてください。

`limit`は表示数の制限になります。

![cwi](/images/metrics/cwi2.png)

課金はスキャンされたデータ1GBあたり0.0076USDです。(2023/01/06)  
CloudWatchは時系列データのため、検索ウィンドウ右上の検索対象スコープに気をつけてください。

むやみに馬鹿でっかいスコープで検索をすると、スキャンされるデータが増えるので課金額の増大に繋がります。

検索結果を眺めてみましょう。

![cwi](/images/metrics/cwi3.png)

このように、`field`に指定したデータを閲覧できます。
`@message`を含めても、含めなくてもそのログが持つfieldについては3番目のログのように、展開することで閲覧することができます。

## e.g. アプリケーションログの統計
単純に検索する例は示したので、次はかんたんな統計の例を示します。

今回、Railsが吐き出した`athena`メソッドを使ったログ出力にはすべて`user_show`というlabelフィールドが存在しています。  
そして、それらのログは`data`フィールドにユーザが指定したクエリパラメータを保存していました。

そこで、ユーザが指定したクエリパラメータでグルーピングし、出現回数をカウントしてみましょう。

```
stats count(*) by payload.data
| filter ispresent(payload.label) and payload.label == 'user_show'
```

このような用途の場合は`stats`を利用することができます。
もちろん、max, min,パーセンタイルなどのメソッドもあります。`splunk`に慣れている人は学習コストが低いかもしれません。

![cwi](/images/metrics/cwi4.png)

## e.g. 性能指標の統計
標準の設定で、durationを記録するようになっているため、下記のようにすることで99%ileを出力することができます。

```
stats pct(duration_ms, 99) by message
| filter ispresent(duration_ms)
```

![cwi](/images/metrics/cwi5.png)

パーセンタイルは、ある程度継続されてアクセスが発生している環境下では、性能劣化の指標として優秀です。


# S3の統計
CloudWatchはこのように、UIを使ってかんたんに高度な検索、統計ができることがわかりました。

ではS3に放り込んでいたactive recordのログは検索できるのでしょうか。
たしかに、殆どの場合は必要ないものですが、かといって検索できないのではいざというときに困りますね。

そこで使用することができるのが[Amazon Athena](https://aws.amazon.com/jp/athena/)です。

(*athenaメソッドで出力しているデータもamazon athenaに流そうかと思っていたのですが、cloudwetchで十分解析できるので結局そこまでやりませんでした*)

## S3の作成
Athenaの解析結果はS3に落ちてくるので、アウトプットファイルを格納するバケットが必要です。 適当なS3を作成してください。

![athena](/images/metrics/athena1.png)

## Athenaの設定
Athena クエリエディタの設定を変更し、S3を指定します。
![athena](/images/metrics/athena2.png)

クエリを実行します。まずはデータベースを作成しましょう。

```sql
CREATE DATABASE `sample_database`
```

作成したデータベースに対してテーブルを作成します。  
json型(struct)はUIから作成できないのでクエリ作成になります。

```sql
CREATE EXTERNAL TABLE IF NOT EXISTS `sample_database`.`metrics-samples` (
	`message` string,
	`payload` struct < 
	  sql: string,
	  binds: map < string,string >,
	  allocations: int,
	  cached: string
	>,
	`duration_ms` double,
	`timestamp` string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
	'ignore.malformed.json' = 'FALSE',
	'dots.in.keys' = 'FALSE',
	'case.insensitive' = 'TRUE',
	'mapping' = 'TRUE'
)
STORED AS INPUTFORMAT 'org.apache.hadoop.mapred.TextInputFormat' OUTPUTFORMAT 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat'
LOCATION 's3://metrics-samples/' -- 任意のバケットに変える
TBLPROPERTIES ('classification' = 'json')
```

athenaの要求するtimestampの型は少々特殊なため、データ定義としてはstringで保持し、`from_iso8601_timestamp`メソッドにより時間型に変換をかけています。
```sql
select message, payload.sql, duration_ms, from_iso8601_timestamp(timestamp) as date_format 
from "metrics-samples" order by date_format;
```
![athena](/images/metrics/athena3.png)

このように、クエリによってActiveRecordのログを検索することができました。

統一したデータ形式で記録されたログファイルであれば効率的に検索することができることがわかると思います。  
逆に、カオスな状態でS3に放り込んでもうまく検索することは難しいでしょう。