import ansi.ANSI

Subscriptions(event) := {
    stdin : Try(Box(ANSI.Input -> event), [NotSubscribed]),
}.{
    none : Subscriptions
    none = Subscriptions.{stdin: Err(NotSubscribed)}
}
