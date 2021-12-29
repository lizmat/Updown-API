use Hash2Class:ver<0.1.4>:auth<zef:lizmat>;
use Cro::HTTP::Client:ver<0.8.7>;

#-------------------------------------------------------------------------------
# Subclasses generated by h2c-skeleton, and tweaked manually after that

class Updown::Check::SSL does Hash2Class[
  error      => Any,
  expires_at => Str,
  tested_at  => Str,
  valid      => Bool,
] { }

class Updown::Check does Hash2Class[
  '@disabled_locations' => Any,
  alias                 => Str,
  apdex_t               => Rat,
  custom_headers        => Hash,
  down                  => Bool,
  down_since            => Any,
  enabled               => Bool,
  error                 => Any,
  favicon_url           => Any,
  http_body             => Str,
  http_verb             => Str,
  last_check_at         => DateTime(Str),
  last_status           => Int,
  next_check_at         => DateTime(Str),
  period                => Int,
  published             => Bool,
  ssl                   => Updown::Check::SSL,
  string_match          => Str,
  token                 => Str,
  uptime                => Rat,
  url                   => Str,
] {
    method mute_until() {
        with $!data<mute_until> {
            if try .DateTime -> $DateTime {
                $DateTime
            }
            else {
                $_
            }
        }
        else {
            Any
        }
    }
}

class Updown::Downtime does Hash2Class[
  duration   => Int,
  ended_at   => DateTime(Str),
  error      => Str,
  id         => Str,
  partial    => Bool,
  started_at => DateTime(Str),
] { }

class Updown::Metrics::Timings does Hash2Class[
  connection => Int,
  handshake  => Int,
  namelookup => Int,
  redirect   => Int,
  response   => Int,
  total      => Int,
] { }

class Updown::Metrics::Requests::ByResponseTime does Hash2Class[
  under1000 => Int,
  under125  => Int,
  under2000 => Int,
  under250  => Int,
  under4000 => Int,
  under500  => Int,
] { }

class Updown::Metrics::Requests does Hash2Class[
  by_response_time => Updown::Metrics::Requests::ByResponseTime,
  failures         => Int,
  samples          => Int,
  satisfied        => Int,
  tolerated        => Int,
] { }

class Updown::Metrics does Hash2Class[
  apdex    => Rat,
  requests => Updown::Metrics::Requests,
  timings  => Updown::Metrics::Timings,
] { }

class Updown::Node does Hash2Class[
  city         => Str,
  country      => Str,
  country_code => Str,
  ip           => Str,
  ip6          => Str,
  lat          => Rat,
  lng          => Rat,
  node_id      => Str,
] { }

class Updown::Webhook does Hash2Class[
  id  => Str,
  url => Str,
] { }

#-------------------------------------------------------------------------------
# Updown

class Updown:ver<0.0.1>:auth<zef:lizmat> {
    has Cro::HTTP::Client $.client    is built(:bind);
    has Updown::Check     %!checks;
    has Updown::Node      %!nodes;

    my $default-client;
    
    method TWEAK(:$api-key) {
        without $!client {
            $default-client := Cro::HTTP::Client.new(
              base-uri => "https://updown.io/api/",
              headers => (
                User-agent => "Raku UpDown Agent v" ~ Updown.^ver,
              ),
            ) without $default-client;
            $!client := $default-client;
        }

        with $api-key // %*ENV<UPDOWN_API_KEY> -> $X-API-KEY {
            $!client.headers.push: (:$X-API-KEY);
        }
        else {
            die "No API key (implicitely) specified";
        }
    }

    method !checks() {
        my $resp := await $!client.get("checks");
        %!checks  = (await $resp.body).map: {
            .<token> => Updown::Check.new($_)
        }
    }

    method !check($token) {
        my $resp := await $!client.get("checks/$token");
        %!checks{$token} = Updown::Check.new(await $resp.body)
    }

    method !nodes() {
        my $resp := await $!client.get("nodes");
        %!nodes  = (await $resp.body).map: -> (:key($node_id), :value(%hash)) {
            %hash<node_id> = $node_id;
            $node_id => Updown::Node.new(%hash)
        }
    }

    method checks(:$update) { $update || !%!checks ?? self!checks !! %!checks }
    method check_ids(:$update) { self.checks(:$update).keys }

    method nodes(:$update) { $update || !%!nodes ?? self!nodes !! %!nodes }
    method node_ids(:$update) { self.nodes(:$update).keys }

    method check($check_id, :$update) {
        $update || !%!checks
          ?? %!checks
            ?? self!check($check_id)
            !! self!checks
          !! %!checks{$check_id}
    }

    method node($node_id, :$update) {
        ($update || !%!nodes ?? self!nodes !! %!nodes){$node_id}
    }

    method ipv4-nodes(:$update) {
        self.nodes(:$update).values.map: *.ip
    }

    method ipv6-nodes(:$update) {
        self.nodes(:$update).values.map: *.ip6
    }

    method downtimes($check_id, :$page = 1 --> List) {
        my $resp := await $!client.get: "checks/$check_id/downtimes",
          query => %(:$page);
        (await $resp.body).map({
            Updown::Downtime.new($_)
        }).List
    }

    method overall_metrics(
      Str:D         $check_id,
      DateTime     :$from,
      DateTime     :$to,
    --> Updown::Metrics:D) {
        my $resp := await $!client.get: "checks/$check_id/metrics",
          query => %((:$from if $from), (:$to if $to));

        Updown::Metrics.new(await $resp.body)
    }

    method hourly_metrics(
      Str:D         $check_id,
      DateTime     :$from,
      DateTime     :$to,
    --> Hash) {
        my $resp := await $!client.get: "checks/$check_id/metrics",
          query => %((:$from if $from), (:$to if $to), :group<time>);

        my Updown::Metrics %metrics{DateTime} = (await $resp.body).map: {
            .key.DateTime => Updown::Metrics.new(.value)
        }
    }

    method node_metrics(
      Str:D         $check_id,
      DateTime     :$from,
      DateTime     :$to,
    --> Hash) {
        my $resp := await $!client.get: "checks/$check_id/metrics",
          query => %((:$from if $from), (:$to if $to), :group<host>);

        my Updown::Metrics %metrics{Str} = (await $resp.body).map: {
            .value.DELETE-KEY("host");
            .key => Updown::Metrics.new(.value)
        }
    }

    method webhooks(--> List) {
        my $resp := await $!client.get("webhooks");
        (await $resp.body).map({ Updown::Webhook.new($_) }).List
    }
}

# vim: expandtab shiftwidth=4

my $ud = Updown.new;

dd $ud.overall-metrics("g280");

=finish
for $ud.checks { #.grep(*.key eq 'g280') {
    say "$_.key(): $_.value.url()";
}
