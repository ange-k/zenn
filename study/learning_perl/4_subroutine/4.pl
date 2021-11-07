# 人の名前を渡すと、その人に挨拶するサブルーチンgreetを書け.
# 挨拶の際には、最後に会った人の名前を知らせる.
# 
# greet("feed");
# greet("Barney");
# 
# 上記の場合下記のようにする.
# Hi Fred! You are this first one here!
# Hi Barney! Fred is also here!

my @queue = ();

sub greet {
    my $name = shift;
    my $size = @queue;
    if ($size == 0) {
        print "Hi $name! You are this first one here!\n";
    }
    else {
        my $before = shift @queue;
        print "Hi $name! $before is also here!\n";
    }
}

while(my $name = <STDIN>) {
    chomp($name);
    greet($name);
    push @queue, $name;
}