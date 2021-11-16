# 文字列のリストを１行に１個ずつ読み込み、文字列それぞれを20文字幅のカラムに右寄せで表示するプログラムを作成せよ.
# 確認のために目盛りを表示すること.
use strict;
use warnings;
use utf8;

sub print_scale {
    my ($scale) = @_;
    
    for my $index ((0..$scale)) {
        my $n = $index % 10;
        print "$n";
    }
    print "\n";
}

sub text_format {
    my ($text, $scale) = @_;
    print_scale($scale);

    my $length = length($text) - 1;
    my $space = $scale - $length;
    if($space > 0) {
        print ' ' x $space, $text;
    } else {
        print $text;
    }
}

text_format('aiueo', 20);