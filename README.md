# fhembsms
bsms Fhem Modul für die Dashboard API von Blaulichtsms. Um dieses Modul zu benutzen muss deine Organisation Blaulichtsms nutzen. Siehe Blaulichtsms für mehr informationen. 

Define

    define <name> bsms <customerID> <username> <password>

    Example: define FWAlert bsms 165123 Dashboarduser 12345


Set

    set <name> <option> <value>

    You can set folgende set befehle gibt es.

    Options:
        Testalarm on|off
        Defaults to "off"


Attributes

    attr <name> <attribute> <value>

    Attributes:
        Alarmdauer
        Die Dauer eines Alarms in Sekunden Default is "3600".
        Intervall
        Der Abfrage Intervall von der Blaulichtsms API. Default is "10".
