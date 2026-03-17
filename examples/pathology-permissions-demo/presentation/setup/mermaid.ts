import { defineMermaidSetup } from '@slidev/types'

export default defineMermaidSetup(() => ({
  theme: 'base',
  themeVariables: {
    lineColor: '#00A9CE',
    primaryColor: '#E0F2F7',
    primaryTextColor: '#001D34',
    primaryBorderColor: '#00A9CE',
    edgeLabelBackground: '#ffffff',
    tertiaryColor: '#ffffff',
    arrowheadColor: '#00A9CE',
  },
  sequence: {
    actorMargin: 40,
    boxMargin: 4,
    boxTextMargin: 3,
    noteMargin: 6,
    messageMargin: 25,
    mirrorActors: false,
    height: 30,
    actorFontSize: 13,
    messageFontSize: 12,
  },
}))
