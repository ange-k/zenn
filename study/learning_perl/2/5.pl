#プロンプトで文字と数字を受け取り、数字の文だけ文字を1行にプリントするプログラムを作成せよ
chomp($str = <STDIN>);
$number = <STDIN>;

foreach my $i(1..$number) {
    print $str,"\n";
}