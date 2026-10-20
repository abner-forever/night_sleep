import Hero from '../components/sections/Hero.jsx'
import Features from '../components/sections/Features.jsx'
import Report from '../components/sections/Report.jsx'
import Privacy from '../components/sections/Privacy.jsx'
import Devices from '../components/sections/Devices.jsx'
import HowItWorks from '../components/sections/HowItWorks.jsx'
import FAQ from '../components/sections/FAQ.jsx'
import CTA from '../components/sections/CTA.jsx'

export default function Home() {
  return (
    <>
      <Hero />
      <Features />
      <Report />
      <Privacy />
      <Devices />
      <HowItWorks />
      <FAQ />
      <CTA />
    </>
  )
}
