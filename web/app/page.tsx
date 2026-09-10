function HingeMark() {
  return <svg width="24" height="24" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="m6 17 3-12h11l-3 12H6Zm0 0-4 2h15l3-2" stroke="currentColor" strokeWidth="1.6" strokeLinejoin="round" /></svg>;
}

function DownloadMark() {
  return <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M12 3v12m-5-5 5 5 5-5M5 16v5h14v-5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" /></svg>;
}

function Preview() {
  return (
    <div className="preview" role="img" aria-label="Illustrated preview: a MacBook lid slowly closes and opens while its desktop bends and blurs.">
      <div className="laptop">
        <div className="lid">
          <div className="camera" />
          <div className="screen">
            <div className="desktop">
              <div className="wallpaper" />
              <div className="sample-window">
                <div className="window-chrome"><i /><i /><i /></div>
                <div className="sample-copy"><span>A small reminder</span><p>Make room<br />for a little<br /><em>play.</em></p></div>
              </div>
            </div>
            <div className="menu"><b>Hinge</b><span>File &nbsp; Edit &nbsp; View</span><span className="clock">9:41</span></div>
            <div className="dock"><i /><i /><i /><i /><i /></div>
          </div>
        </div>
        <div className="base"><div className="notch" /></div>
      </div>
    </div>
  );
}

export default function Home() {
  const video = process.env.DEMO_VIDEO_URL;
  return (
    <div className="page">
      <header><a className="brand" href="/" aria-label="Hinge home"><HingeMark />hinge</a><a className="source-link" href="https://github.com/Noveum/hinge">GitHub <span aria-hidden="true">↗</span></a></header>
      <main>
        <div className="intro">
          <p className="eyebrow">A tiny app. A nice little detail.</p>
          <h1>Your lid moves.<br /><span>Your desktop follows.</span></h1>
          <p className="description">A soft bend. A little blur.<br />A more playful way to close your MacBook.</p>
          <a className="download" href="/download"><DownloadMark />Download for Mac</a>
          <p className="requirements">Apple silicon · macOS 14+ · Supported lid sensor</p>
        </div>
        <figure>
          {video ? <video className="demo-video" src={video} controls playsInline preload="metadata" aria-label="Hinge in action" /> : <Preview />}
          <figcaption>{video ? "Your desktop, with a little more feeling." : "An illustrated preview. Real recording coming soon."}</figcaption>
        </figure>
      </main>
      <footer><span>Made for the little things.</span><a href="https://github.com/Noveum/hinge/issues">Got an idea? Say hello <span aria-hidden="true">↗</span></a></footer>
    </div>
  );
}
