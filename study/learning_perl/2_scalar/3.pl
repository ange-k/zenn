#問題2を改造し、負の入力を受け取った場合には0を表示するようにせよ.
use constant PI => 3.14159265359;

my $number = <STDIN>;

if($number < 0) {
    print 0;
    exit;
}

print $number * 2 * PI;
