export interface Config {
  baseUrl: string;
  timeout: number;
}

export const defaultConfig: Config = {
  baseUrl: 'https://api.example.com',
  timeout: 5000,
};
