Es muss zusätzlich noch das Paket libdatetime-format-strptime-perl installiert werden mit:

    sudo apt install libdatetime-format-strptime-perl


# fhembsms
bsms Fhem Modul für die Dashboard API von Blaulichtsms. Um dieses Modul zu benutzen muss deine Organisation Blaulichtsms nutzen. Siehe Blaulichtsms für mehr informationen. 
    https://blaulichtsms.net/

Define

    define <name> bsms <customerID> <username> <password>

    Example: define FWAlert bsms 165123 Dashboarduser 12345


Set

    set <name> <option> <value>

    folgende set befehle gibt es.

    Options:
        Testalarm on|off
        Defaults to "off"


Attributes

    attr <name> <attribute> <value>

    Attributes:
        Alarmdauer
        Die Dauer eines Alarms in Sekunden Default ist "3600".
        Intervall
        Der Abfrage Intervall von der Blaulichtsms API. Default is "10".
