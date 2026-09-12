interface IconProps {
  className?: string;
}

export function AppleLogo({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701" />
    </svg>
  );
}

export function WindowsLogo({ className }: IconProps) {
  return (
    <svg
      className={className}
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M0 0h11v11H0zM13 0h11v11H13zM0 13h11v11H0zM13 13h11v11H13z" />
    </svg>
  );
}

export function SyncTogetherIcon({ className }: IconProps) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 1024 1024"
      className={className}
      aria-hidden="true"
    >
      <defs>
        <linearGradient
          id="synctogether-icon-grad"
          x1="0.0"
          y1="0.0"
          x2="1024.0"
          y2="1024.0"
          gradientUnits="userSpaceOnUse"
        >
          <stop offset="0" stopColor="#8B5CF6" />
          <stop offset="1" stopColor="#C084FC" />
        </linearGradient>
      </defs>
      <rect
        x="0.0"
        y="0.0"
        width="1024"
        height="1024"
        rx="327.68"
        ry="327.68"
        fill="url(#synctogether-icon-grad)"
      />
      <g transform="translate(230.39999999999998 793.6) scale(1.1 -1.1)">
        <path
          d="M171 367V145C171 129 189 118 204 128L377 238C390 246 390 266 377 274L204 384C189 394 171 383 171 367Z"
          fill="#FFFFFF"
        />
      </g>
    </svg>
  );
}

