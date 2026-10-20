export const SITE = {
  repositoryUrl: 'https://github.com/abner-forever/night_sleep',
  issuesUrl: 'https://github.com/abner-forever/night_sleep/issues',
  downloadPageUrl: () => {
    const url = new URL(window.location.href)
    url.hash = '/download'
    return url.href
  },
  year: new Date().getFullYear(),
}
