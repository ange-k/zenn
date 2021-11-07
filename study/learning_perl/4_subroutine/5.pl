# 4を改造し、新しくあった人にそれまでに挨拶した全員の名前を知らせる

my @queue = ();

sub queuing {
    my $name = shift;
    if(grep { $_ eq $name } @queue) {
        return;
    }
    push @queue, $name;
}

sub greet {
    my $name = shift;
    my $size = @queue;
    if ($size == 0) {
        print "Hi $name! You are this first one here!\n";
    }
    else {
        print "Hi $name! I've seen: @queue\n";
    }
}

while(my $name = <STDIN>) {
    chomp($name);
    greet($name);
    queuing($name);
}