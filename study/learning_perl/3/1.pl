# 1行に一個からなる文字列のリストを入力の終わりになるまで読み込み、そのリストを逆順で表示せよ
@list = <STDIN>;
foreach my $value(reverse(@list)){
    print "$value";
}