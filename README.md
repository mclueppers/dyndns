dyndns.sh
=========

Dynamically set primary or backup IP for a DNS entry

# Examples

## One primary and one secondary IP

  dyndns.sh -o puppetmaster -z lab.dobrev.eu -p 10.0.0.1 -b 10.0.0.2

As long as 10.0.0.1 is reachable puppetmaster.lab.dobrev.eu is going to point to it. Else 10.0.0.2 is being used

## One primary and more than one backup IP

  dyndns.sh -o puppetmaster -z lab.dobrev.eu -p 10.0.0.1 -b 10.0.0.2 -b 10.0.0.3

`-b` can be used more than once. In that case the script will fall back to the first available backup IP.

# License

This software is dual-licensed under [Affero GPL](LICENSE) and [MIT License](LICENSE.MIT) with the hope to be useful for a wider audience.
