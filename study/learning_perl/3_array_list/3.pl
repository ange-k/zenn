# 文字列のリストを1行1個ずつ入力の終わりになるまで読み込む。
# 読み込んだ文字列をコードポイント順に表示するプログラムを作成せよ。
my @list = <STDIN>;
foreach my $value(sort(@list)){
    print "$value";
}