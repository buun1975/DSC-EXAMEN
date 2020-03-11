[DSCLocalConfigurationManager()]
configuration LCMConfigBruno
{
    Node localhost
    {
        Settings
        {
            RefreshMode = 'Push'
            RebootNodeIfNeeded = $True
RefreshFrequencyMins =             30
ConfigurationMode = 'ApplyAndAutoCorrect'

        }
    }
}
lcmconfigBruno
