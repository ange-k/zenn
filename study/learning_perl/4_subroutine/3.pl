# 数のリストを受け取って、その中から平均よりも大きなものを返すサブルーチン、
# above_averageを書け.
# hint: 数の合計を個数で割って平均を計算する別のサブルーチンが必要.
# 作成したサブルーチンを以下のテストプログラムに入れて動かせ.

use List::Util qw/sum/;

=pod
@arg number_list 数のリスト
@return 数の合計を個数で割って平均を計算する
=cut
sub average {
    my @number_list = @_;
    my $list_size = @number_list;

    sum(@number_list) / $list_size;    
}

sub above_average {
    my @number_list = @_;
    my $average = average(@number_list);

    grep { $_ > $average } @number_list;
}

my @fred = above_average(1..10);
my @barney = above_average(100, 1..10);

print "fred=@fred\n";
print "barney=@barney\n";
