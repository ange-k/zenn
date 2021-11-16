use strict;
use warnings;
use utf8;

# catコマンドを作成せよ. ただし、行を逆順に出力すること. (tacコマンドと同一.)
sub tac {
    my $path = shift;
    open(my $file, "<", $path)
        or die "Can't open:$!";

    for my $line (reverse <$file>) {
        chomp $line;
        print "$line\n";
    }
}

tac('./example.txt');