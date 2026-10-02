import React from 'react';

const PALETTE = ['#5b6ee1', '#2f9e8f', '#d9663b', '#b24c8f', '#3d8bd4', '#7a5cc7', '#c2852b'];

// Deterministic color per username so the same person always looks the same.
const colorFor = name => {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = (hash * 31 + name.charCodeAt(i)) | 0;
  }
  return PALETTE[Math.abs(hash) % PALETTE.length];
};

// Rendered as an <img> data URI so every existing size rule
// (.user-pic, .user-img, .comment-author-img, .article-meta img) still applies.
export const fallbackAvatar = (username = '?') => {
  const initial = (username.trim()[0] || '?').toUpperCase();
  const svg =
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">` +
    `<rect width="64" height="64" fill="${colorFor(username)}"/>` +
    `<text x="50%" y="50%" dy=".35em" text-anchor="middle" fill="#fff" ` +
    `font-family="Inter,Arial,sans-serif" font-size="30" font-weight="600">${initial}</text>` +
    `</svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
};

class Avatar extends React.Component {
  constructor(props) {
    super(props);
    this.state = { failedSrc: null };
    this.handleError = () => this.setState({ failedSrc: this.props.src });
  }

  render() {
    const { src, username, className } = this.props;
    const usable = src && src !== this.state.failedSrc;

    return (
      <img
        src={usable ? src : fallbackAvatar(username)}
        onError={usable ? this.handleError : undefined}
        className={className}
        alt={username} />
    );
  }
}

export default Avatar;
