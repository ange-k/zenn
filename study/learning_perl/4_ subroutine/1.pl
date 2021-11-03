use List::Util qw/sum/;
# 数値のリストを受け取って、その合計を返すサブルーチンtotalを完成させよ.
# hint: このサブルーチンでI/Oを行わないこと.
=pod
=head1 total
@arg number_list 数のリスト
@return number_listにある数の合計値
=cut
sub total{
    my @number_list = @_;
    sum(@number_list)
}

my @fred = qw (1 2 5 7 9);
my $fred_total = total(@fred);

print "The total of \@fred is $fred_total.\n";
print 'Enter some numbers on separate lines:';

my $user_total = total(<STDIN>);
print "The total of those number is $user_total.\n"