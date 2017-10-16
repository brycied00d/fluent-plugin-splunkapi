FROM ruby

ENV HOME=/opt/fluent-plugin-splunk-http-eventcollector

COPY Gemfile ${HOME}/Gemfile
COPY fluent-plugin-splunk-http-eventcollector.gemspec ${HOME}/fluent-plugin-splunk-http-eventcollector.gemspec

WORKDIR ${HOME}

RUN bundle install

COPY . ${HOME}

CMD ["rake", "test"]
