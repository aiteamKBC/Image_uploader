import { useState } from 'react'

interface Props {
  url: string
  className?: string
}

/** A button that copies `url` to the clipboard and briefly shows "Copied". */
export default function CopyButton({ url, className }: Props) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    try {
      await navigator.clipboard.writeText(url)
    } catch {
      // Fallback for browsers/contexts without the async Clipboard API.
      const el = document.createElement('textarea')
      el.value = url
      document.body.appendChild(el)
      el.select()
      document.execCommand('copy')
      document.body.removeChild(el)
    }
    setCopied(true)
    window.setTimeout(() => setCopied(false), 1500)
  }

  return (
    <button type="button" className={className ?? 'btn'} onClick={copy}>
      {copied ? '✓ Copied' : 'Copy URL'}
    </button>
  )
}
