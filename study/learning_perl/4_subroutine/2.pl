# 1で作成したサブルーチンを使用して、1から1000までの合計を求めるプログラムを書け.

use List::Util qw/sum/;
=pod
=head1 total
@arg number_list 数のリスト
@return number_listにある数の合計値
=cut
sub total{
    my @number_list = @_;
    sum(@number_list)
}

my @number_list = (1..1000);
print total(@number_list);
