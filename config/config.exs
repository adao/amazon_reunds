import Config

config :wallaby,
  chromedriver: [
    headless: false
  ]

config :amazon_refunds, username: System.get_env("AR_USERNAME"), password: System.get_env("AR_PASSWORD")
