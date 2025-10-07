# GapMinder

An app written in Flutter and Dart to grab nearby rail Departures. 

## Building this app

To use this app, you will need to have an API account with RealTimeTrains. You can do this [here](https://api.rtt.io).

Once you have your Username and Password, you need to create a `secrets.json` file in `assets`. It should look like this:
```json
{
  "username" : "YOUR_USER_HERE",
  "password" : "YOUR_PASSWORD_HERE"
}
```

If you wish to build a Release version, you will need to create a `keys.properties` file, as well as configure your system accordingly.
This is left as an exercise to the Builder :). 