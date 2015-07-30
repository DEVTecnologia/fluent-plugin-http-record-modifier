# Fluent::Plugin::Simple Value to Hash

Fluent plugin for converting simple value variables to hash to be usable to others plugins

## Installation

Add this line to your application's Gemfile:

    gem 'fluent-plugin-http-record-modifier'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install fluent-plugin-http-record-modifier

## Usage

```

<filter tag>
  type http_record_modifier
  method (defaults to GET)
  renew_record (defaults to false)
  endpoint_url yourapi.com/api/something/
  serializer (form or json, just used on POST)
  authentication (none or basic, defaults to none)
  username (default to '')
  password (default to '')
  <params>
    var ${tag_parts[1]}
    var2 ${record_attr}
  </params>
  <record>
    name ${body.name}
    body ${body}
    array ${body.array}
    second ${body.array[1]}
    last ${body.array[-1]}
    deep ${body.array[0].attr}
  </record>
</filter>

```

## Contributing

1. Fork it ( http://github.com/DEVTecnologia/fluent-plugin-http-record-modifier/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
