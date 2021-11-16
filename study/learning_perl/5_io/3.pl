# 問題2のプログラムを改造し、ユーザがカラムの幅を変更できるようにせよ.
# 例えば、30, hello, good-byeをそれぞれ別の行に入力すると、
# 30文字幅のカラムに右寄せで表示する.
use strict;
use warnings;
use utf8;

# 2.plと同じだが、対応できているので...

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
        print ' ' x $space, $text, "\n";
    } else {
        print $text, "\n";
    }
}

text_format('30', 30);
text_format('hello', 30);
text_format('good-bye', 30);
