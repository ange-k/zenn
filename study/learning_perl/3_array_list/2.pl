# 1行1個からなる数のリストをEOFまで読みこみ、以下に示すリストに対応した文字を表示せよ.
# 1であればfred, 3であればbarneyを表示する.
# fred betty barney dino wilma pebbles bamm-bamm
use constant USERS => qw (
    fred
    betty
    barney
    dino
    wilma
    pebbles
    bamm-bamm
);

@list = <STDIN>;
foreach my $index(@list) {
    print '', (USERS)[$index-1], "\n";
}
# https://perldoc.jp/docs/modules/constant-1.17/constant.pod#NOTES
# 上記によると, 定数はそのままでは文字列としての展開ができない.
# print (USERS)[$index], "\n";とかくと, そもそもコンパイルが通らない. マジで.
