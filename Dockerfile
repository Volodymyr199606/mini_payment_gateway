# syntax=docker/dockerfile:1

FROM ruby:3.2

# System deps
RUN apt-get update -qq && apt-get install -y \
  build-essential \
  libpq-dev \
  nodejs \
  npm \
  git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle install

# Copy app
COPY . .

# Precompile assets (safe even if no assets)
RUN bundle exec rake assets:precompile || true

ENV RAILS_ENV=production
ENV RACK_ENV=production

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

