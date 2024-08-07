use strict;
use warnings;

use Net::AMQP::RabbitMQ;
use Test::More;
use Sys::Hostname;

use FindBin qw/$Bin/;
use lib "$Bin/../t/lib";
use NAR::Helper;

my $helper = NAR::Helper->new;
$helper->plan(9);

my $unique   = hostname . "-$^O-$^V";    #hostname-os-perlversion
my $exchange = "nr_test_x-$unique";
my $routekey = "nr_test_q-$unique";

diag "this test is slow, and probably only works on linux";

use_ok('Net::AMQP::RabbitMQ');

ok $helper->connect, "connected";
my $mq = $helper->mq;
eval { $mq->channel_open(1); };
is( $@, '', "channel_open" );
my $queuename = '';
eval {
  $queuename = $mq->queue_declare( 1, '',
    { passive => 0, durable => 1, exclusive => 0, auto_delete => 1 } );
};
is( $@, '', "queue_declare" );
isnt( $queuename, '', "queue_declare -> private name" );
eval {
  $mq->exchange_declare(
    1,
    $exchange,
    {
      exchange_type => "direct",
      passive       => 0,
      durable       => 1,
      auto_delete   => 0,
      internal      => 0
    }
  );
};
is( $@, '', "exchange_declare" );
eval { $mq->queue_bind( 1, $queuename, $exchange, $routekey ); };
is( $@, '', "queue_bind" );

my $start_mem = get_mem();
my $i         = 0;
while ( $i < 50_000 ) {
  $mq->tx_select(1);
  $mq->publish(
    1, $routekey,
    "Magic Transient Payload (Commit)",
    { exchange => $exchange }
  );
  $mq->tx_commit(1);
  if ( ( $i % 10_000 ) == 0 ) {
    diag(
      sprintf(
        "%i - used: %.2fmb, diff: %.2fmb",
        $i, get_mem(), get_mem() - $start_mem
      )
    );
  }
  ++$i;
}
my $diff = get_mem() - $start_mem;
ok( $diff < 1, "memory usage hasn't risen by more than 1mb (${diff}mb)" );

sub get_mem {
  my $mem = `grep VmRSS /proc/$$/status`;
  return [ split( qr/\s+/, $mem ) ]->[1] / 1024;
}
