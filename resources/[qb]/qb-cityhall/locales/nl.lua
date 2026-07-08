local Translations = {
    error = {
        not_in_range = 'U bent te ver van het stadhuis verwijderd.'
    },
    success = {
        recived_license = 'U heeft uw %{value} ontvangen voor $50.'
    },
    info = {
        new_job_app = 'Uw sollicitatie is verzonden naar de baas van %{job}.',
        bilp_text = 'Stadsdiensten',
        city_services_menu = '~g~E~w~ - Stadsdiensten Menu',
        id_card = 'Identiteitskaart',
        driver_license = 'Rijbewijs',
        weaponlicense = 'Vuurwapenvergunning',
        new_job = 'Gefeliciteerd met uw nieuwe baan! (%{job})'
    },
    email = {
        jobAppSender = "%{job}",
        jobAppSub = "Bedankt voor uw sollicitatie bij %{job}.",
        jobAppMsg = "Geachte %{gender} %{lastname},<br /><br />Uw sollicitatie bij %{job} is ontvangen.<br /><br />De leidinggevende zal uw aanvraag bekijken en zo spoedig mogelijk contact met u opnemen voor een gesprek.<br /><br />Nogmaals dank voor uw sollicitatie.",
        mr = 'Dhr.',
        mrs = 'Mevr.',
        sender = 'Gemeente',
        subject = 'Aanvraag rijles',
        message = "Geachte %{gender} %{lastname},<br /><br />We hebben zojuist bericht ontvangen dat iemand rijles wil volgen.<br />Als u bereid bent les te geven, neem dan alstublieft contact met ons op:<br />Naam: <strong>%{firstname} %{lastname}</strong><br />Telefoonnummer: <strong>%{phone}</strong><br /><br />Met vriendelijke groet,<br />Gemeente Los Santos"
    }
}

if GetConvar('qb_locale', 'en') == 'nl' then
    Lang = Locale:new({
        phrases = Translations,
        warnOnMissing = true,
        fallbackLang = Lang,
    })
end
